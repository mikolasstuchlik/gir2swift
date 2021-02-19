#!/bin/bash

## TODO
## Function used to determine, whether provided path contains valid package
## ARGUMENT 1: Path to the Swift package in question
function validate_is_processable_arg-path {
    local PACKAGE_PATH=$1

    local CALLER=$PWD
    cd $PACKAGE_PATH

    local PACKAGE=`swift package dump-package`
    local GENERATED=`jq -r '.dependencies | .[] | select(.name == "gir2swift") | .name' <<< $PACKAGE`
    local MANIFEST="gir2swift-manifest.sh"

    if [[ $GENERATED && -f "$MANIFEST" ]]
    then
        cd $CALLER
        return 0
    else
        cd $CALLER 
        return 1
    fi
}

## Function used to determine, whether provided path requires processing by gir2swift
## ARGUMENT 1: Path to the Swift package in question
## RETURN: `true` if package contains file named "gir2swift-manifest.sh" 
function is_processable_arg-path {
    local PACKAGE_PATH=$1

    local CALLER=$PWD
    cd $PACKAGE_PATH

    local MANIFEST="gir2swift-manifest.sh"

    if [[ -f "$MANIFEST" ]]
    then
        cd $CALLER
        return 0
    else
        cd $CALLER 
        return 1
    fi
}

## Function which searches for .gir file in current system and returns full path to gir file.
## ARGUMENT 1: Path to package containing gir2swift-manifest.sh
## RETURN: Full path to gir file or 1
function gir_file_arg-pkg-path {
    local PKG_PATH=$1

    local GIR_NAME=$(get_gir_names_arg-package ${PKG_PATH})
    local GIR_PKG=$(get_gir_pkg_arg-package ${PKG_PATH})

    # Attempt to search in default directories
    for DIR in "/opt/homebrew/share/gir-1.0" "/usr/local/share/gir-1.0" "/usr/share/gir-1.0" ; do
        CURRENT=$DIR
        if ! [ -f "${DIR}/${GIR_NAME}.gir" ] ; then
            unset CURRENT
        fi

        if ! [ -z ${CURRENT} ] ; then
            echo "$CURRENT/${GIR_NAME}.gir"
            exit 0
        fi
    done

    # In case platform is macOS, library may be contained in a sandbox
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local PKG_PATH=`pkg-config --variable=libdir ${GIR_PKG}`
        local ASSUMED_PATH="${PKG_PATH}/../share/gir-1.0/${GIR_NAME}.gir"

        if [ -f "${ASSUMED_PATH}" ] ; then
            echo "${ASSUMED_PATH}"
            exit 0
        fi
    fi

    exit 1
}

## Searches Swift packages provided in the argument for gir2swift package. In case the package is found, the package is built and path to executable is returnes
## ARGUMENT 1: JSON of dependency graph fetched by the root Package.
## RETURN: Path to gir2swift executable
function gir_2_swift_executable_arg-deps {
    local DEPENDENCIES=$1

    local G2S_PACKAGE_PATH=`jq -r 'first(recurse(.dependencies[]) | select(.name == "gir2swift")) | .path' <<< $DEPENDENCIES`

    local CALLER=$PWD
    cd $G2S_PACKAGE_PATH

    ./distclean.sh > /dev/null
    ./build.sh > /dev/null

    cd $CALLER

    echo "${G2S_PACKAGE_PATH}/.build/release/gir2swift"
}

## Filters list of dependencies provided in the argument and returns only those which require processing by gir2swift.
## ARGUMENT 1: JSON of dependency graph fetched by the root package.
## ARGUMENT 2: Name of the Swift package which dependencies should be returned.
## RETURN: List of all paths to the Swift packages which should be processed.
function get_processable_dependencies_arg-deps_arg-name {
    local DEPENDENCIES=$1
    local PACKAGE_NAME=$2

    local PACKAGE=`jq -r "first(recurse(.dependencies[]) | select(.name == \"$PACKAGE_NAME\"))" <<< $DEPENDENCIES`

    local ALL_DEPS=`jq -r "recurse(.dependencies[]) | select(.name != \"$PACKAGE_NAME\") | .path" <<< $PACKAGE | sort | uniq`

    for DEP in $ALL_DEPS
    do
        if $(is_processable_arg-path $DEP)
        then
            echo $DEP
        fi
    done
}

## Returns names of GIR file of provided package.
## ARGUMENT 1: Path to the package in question. ONLY PROCESSABLE PACKAGE IS VALID INPUT.
## RETURN: Names of gir file.
function get_gir_names_arg-package {
    local PACKAGE=$1

    bash -c "$PACKAGE/gir2swift-manifest.sh gir-name"
}

## Returns name of pkg-config package which is related to the gir file.
## ARGUMENT 1: Path to the package in question. ONLY PROCESSABLE PACKAGE IS VALID INPUT.
## RETURN:Name of pkg-config package.
function get_gir_pkg_arg-package {
    local PACKAGE=$1

    bash -c "$PACKAGE/gir2swift-manifest.sh gir-pkg"
}

## Returns name of Swift package. This function depends on working directiory it is run in. This function is exported and required by manifests.
function package_name {
    local PACKAGE=`swift package dump-package`
    local NAME=`jq -r '.name' <<< $PACKAGE`

    echo $NAME
}
export -f package_name

## Returns all pkg-config packages required by targets specified in a Swift package. This feature is intended as a support for macOS. This function depend on working directory. This function is exported and required by manifests.
function package_pkg_config_arguments {
    local PACKAGE=`swift package dump-package`
    local NAME=`jq -r '.targets[] | select(.pkgConfig != null) | .pkgConfig?' <<< $PACKAGE`

    echo $NAME
}
export -f package_pkg_config_arguments

## This function name of Swift package on specified path.
## ARGUMENT 1: Path to the package in question.
## RETURN: Name of the package
function package_name_arg-path {
    local PACKAGE_PATH=$1

    local CALLER=$PWD
    cd $PACKAGE_PATH
    
    local PACKAGE=`swift package dump-package`
    local NAME=`jq -r '.name' <<< $PACKAGE`

    cd $CALLER

    echo $NAME
}


# Command
COMMAND=$1

case $COMMAND in
generate) 
    TOP_LEVEL_PACKAGE_PATH=$2
    OPTIONAL_ALTERNATIVE_G2S_PATH=$3

    # Fetch and retain dependency graph, since this operation takes a lot of time.
    cd $TOP_LEVEL_PACKAGE_PATH
    TOP_LEVEL_PACKAGE_NAME=$(package_name)
    DEPENDENCIES=`swift package show-dependencies --format json`
    PROCESSABLE=$(get_processable_dependencies_arg-deps_arg-name "$DEPENDENCIES" "$TOP_LEVEL_PACKAGE_NAME")

    ALL_PROCESSABLE="$PROCESSABLE"
    if $(is_processable_arg-path "$TOP_LEVEL_PACKAGE_PATH")
    then
        ALL_PROCESSABLE="$TOP_LEVEL_PACKAGE_PATH $PROCESSABLE"
    fi

    # Resolve paths to gir files
    declare -A gir_files
    for PACKAGE in $ALL_PROCESSABLE
    do
        GIR_FILE=$(gir_file_arg-pkg-path $PACKAGE)
        if ! [[ $GIR_FILE ]]; then
            echo "Gir file for $PACKAGE not found!"
            exit 1
        fi
        gir_files[${PACKAGE}]=${GIR_FILE}
    done

    # Determine path to gir2swift executable
    if [ -z "$OPTIONAL_ALTERNATIVE_G2S_PATH" ]
    then
        echo "Building gir2swift"
        G2S_PATH=$(gir_2_swift_executable_arg-deps "$DEPENDENCIES")
    else
        G2S_PATH=$OPTIONAL_ALTERNATIVE_G2S_PATH
        echo "Using custom gir2swift executable at: $G2S_PATH"
    fi

    for PACKAGE in $ALL_PROCESSABLE
    do
        PACKAGE_NAME=$(package_name_arg-path "$PACKAGE")
        PACKAGE_DEPS=$(get_processable_dependencies_arg-deps_arg-name "$DEPENDENCIES" "$PACKAGE_NAME")
        DEP_PATHS=`for PATH in ${PACKAGE_DEPS}; do echo -n " ${gir_files[${PATH}]}"; done`
        GIR_PATH=${gir_files[${PACKAGE}]}
        echo -n "Generating Swift Wrapper for $PACKAGE_NAME ... "
        bash -c "$PACKAGE/gir2swift-manifest.sh generate \"$PACKAGE\" \"$G2S_PATH\" \"$DEP_PATHS\" \"$GIR_PATH\" "
    done

    ;;
remove-generated) 
    TOP_LEVEL_PACKAGE_PATH=$2

    cd $TOP_LEVEL_PACKAGE_PATH
    DEPENDENCIES=`swift package show-dependencies --format json`
    PROCESSABLE=$(get_processable_dependencies_arg-deps_arg-name "$DEPENDENCIES" "$(package_name)")

    ALL_PROCESSABLE="$PROCESSABLE"
    if $(is_processable_arg-path "$TOP_LEVEL_PACKAGE_PATH")
    then
        ALL_PROCESSABLE="$TOP_LEVEL_PACKAGE_PATH $PROCESSABLE"
    fi

    for PACKAGE in $ALL_PROCESSABLE 
    do
        cd $PACKAGE
        PACK_NAME=$(package_name_arg-path $PACKAGE)
        bash -c "rm Sources/$PACK_NAME/*-*.swift"
    done 
    ;;

c-flags)
    TOP_LEVEL_PACKAGE_PATH=$2

    cd $TOP_LEVEL_PACKAGE_PATH
    DEPENDENCIES=`swift package show-dependencies --format json`
    PROCESSABLE=$(get_processable_dependencies_arg-deps_arg-name "$DEPENDENCIES" "$(package_name)")

    ALL_PROCESSABLE="$PROCESSABLE"
    if $(is_processable_arg-path "$TOP_LEVEL_PACKAGE_PATH")
    then
        ALL_PROCESSABLE="$TOP_LEVEL_PACKAGE_PATH $PROCESSABLE"
    fi

    PKGS=""
    for PACKAGE in $ALL_PROCESSABLE
    do
        cd $PACKAGE
        PKGS="$PKGS $(package_pkg_config_arguments)"
    done

    C=`pkg-config --cflags $PKGS`
    LINKER=`pkg-config --libs $PKGS`

    # Decorating flags returned from pkg-config with -Xcc and -Xlinker flags
    DECORC=`for FLAG in ${C}; do echo -n "-Xcc ${FLAG} "; done`
    DECORL=`for FLAG in ${LINKER}; do echo -n "-Xlinker ${FLAG} "; done`

    # pkg-config on mac generates sequences like "-Wl,-framework,Cocoa" - those sequences are not desirable and refactored into "-framework -Xlinker Cocoa" which with previous decoration results in sequences of "-Xlinker -framework -Xlinker Cocoa"
    MAC_LINKER_FIXES=`echo "${DECORL}" | sed -e 's/ *-Wl, */ /g' -e 's/,/ -Xlinker /g'`    

    echo "${DECORC} ${MAC_LINKER_FIXES}"
    ;;

validate)
    echo "TODO: not implemented"
    ;;

## THIS CODE IS MODIFIED LEGACY IMPLEMENTATION
## generate-xcodeproj is deprecated https://github.com/apple/swift-package-manager/pull/3062
patchxcproj)
    TOP_LEVEL_PACKAGE_PATH=$2

    cd $TOP_LEVEL_PACKAGE_PATH

    DEPENDENCIES=`swift package show-dependencies --format json`
    PROCESSABLE=$(get_processable_dependencies_arg-deps_arg-name "$DEPENDENCIES" "$(package_name)")

    ALL_PROCESSABLE="$PROCESSABLE"
    if $(is_processable_arg-path "$TOP_LEVEL_PACKAGE_PATH")
    then
        ALL_PROCESSABLE="$TOP_LEVEL_PACKAGE_PATH $PROCESSABLE"
    fi

    PKGS=""
    for PACKAGE in $ALL_PROCESSABLE
    do
        cd $PACKAGE
        PKGS="$PKGS $(package_pkg_config_arguments)"
    done

    CCFLAGS=`pkg-config --cflags $PKGS`

    local PACKAGE_NAME=$(package_name)
    [ ! -e ${PACKAGE_NAME}.xcodeproj/Configs ] ||					   \
    ( cd ${PACKAGE_NAME}.xcodeproj/Configs						&& \
        mv Project.xcconfig Project.xcconfig.in				&& \
        echo 'SWIFT_VERSION = 3.0' >> Project.xcconfig.in			&& \
        sed -e 's/ -I ?[^ ]*//g' < Project.xcconfig.in > Project.xcconfig	&& \
        grep 'OTHER_CFLAGS' < Project.xcconfig.in | sed 's/-I */-I/g'		|  \
        tr ' ' '\n' | grep -- -I | tr '\n' ' '				|  \
        sed -e 's/^/HEADER_SEARCH_PATHS = /' -e 's/ -I/ /g' >> Project.xcconfig
    )
    ( cd ${PACKAGE_NAME}.xcodeproj							&& \
        mv project.pbxproj project.pbxproj.in					&& \
        sed < project.pbxproj.in > project.pbxproj				   \
        -e "s|\(HEADER_SEARCH_PATHS = .\)$|\\1 \"`echo $CCFLAGS | sed -e 's/-Xcc  *-I */ /g' -e 's/^ *//' -e 's/ *$//'`\",|"
    )
    ;;

## THIS CODE IS MODIFIED LEGACY IMPLEMENTATION
docgen)
    TOP_LEVEL_PACKAGE_PATH=$2

    cd $TOP_LEVEL_PACKAGE_PATH

    local BUILD_DIR="${PWD}/.build"
    local PACKAGE_NAME=$(package_name)
    local JAZZY_VER=3.24.24
    local GIR_NAME=$(get_gir_names_arg-package ${PKG_PATH})
    local DEPENDENCIES=`swift package show-dependencies --format json`
    local G2S_PACKAGE_PATH=`jq -r 'first(recurse(.dependencies[]) | select(.name == "gir2swift")) | .path' <<< $DEPENDENCIES`
    [ -e Sources/${PACKAGE_NAME}/${GIR_NAME}.swift ] || ./generate-wrapper.sh
    [ -e "$BUILD_DIR/build.db" ] || ./build.sh

    JAZZY_ARGS="--theme fullwidth --author Ren&eacute;&nbsp;Hexel --author_url https://experts.griffith.edu.au/9237-rene-hexel --github_url https://github.com/rhx/Swift$PACKAGE_NAME --github-file-prefix https://github.com/rhx/Swift$PACKAGE_NAME/tree/generated --root-url http://rhx.github.io/Swift$PACKAGE_NAME/ --output docs"
    rm -rf .docs.old
    mv docs .docs.old 2>/dev/null
    [ -e .build ] || ln -s "$BUILD_DIR" .build
    sourcekitten doc --spm --module-name $PACKAGE_NAME -- --build-path "$BUILD_DIR"  \
	    `$G2S_PACKAGE_PATH/gir2swift-generation-driver.sh c-flags ${PWD}` > "$BUILD_DIR/$PACKAGE_NAME-doc.json"
    jazzy   --sourcekitten-sourcefile "$BUILD_DIR/$PACKAGE_NAME-doc.json" --clean	\
            --module-version $JAZZY_VER --module $PACKAGE_NAME $JAZZY_ARGS
    rm -f .build 2>/dev/null
    ;;

g2s-init)
    echo "TODO: not implemented"
    ;;
*)
    echo "OVERVIEW: Gir 2 swift code generation driver tool"
    echo ""
    echo "USAGE: ./gir2swift-generation-driver.sh COMMAND [PATH TO ROOT PACKAGES] [ARGUMENTS]..."
    echo ""
    echo "COMMANDS:"
    echo "  generate [optional path to gir2swift executable]"
    echo "                      Builds and runs gir2swift"
    echo "  remove-generated    Removes generated files"
    echo "  c-flags             Prints c-flags for Swift compiler on macOS to the standard output"
    echo "  validate            Validates package and dependencies using gir2swift"
    echo "  patchxcproj         Patches Xcode project"
    echo "  docgen              Generates documentation using Jazzy"
    echo "  g2s-init [GIR NAME] [pkg-config NAME]"
    echo "                      Generates template and validates Swift project"
    ;;
esac
