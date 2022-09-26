# This script get Vika SemVer from Circle CI/Github Action Environment Variables
# Git Flow Convention based
# Author: Kelly Peilin Chan<kelly@vikadata.com>
# Created: 2022-05-17
# Modified: 2022-08-30
# Usage:
#     eval "$$(curl -fsSL https://vikadata.github.io/semver_ci.sh)"
#   	build_docker XXX

# get the semver-cli
wget https://raw.githubusercontent.com/fsaintjacques/semver-tool/3.3.0/src/semver -qO /tmp/semver


# read .version file
function env_dotversion {
  export SEMVER_NUMBER=$(cat .version)
  _read_semver
}

# read gradle.properties
function env_java {
  export SEMVER_NUMBER=$(cat gradle.properties | grep "revision" | cut -d'=' -f2)
  _read_semver
}

# Node JS Package
function env_nodejs {
  # read node js pacakge version number
  export SEMVER_NUMBER=$(awk -F'"' '/"version": ".+"/{ print $4; exit; }' package.json)
  _read_semver
}

# Get SemVer from Circle CI Environment Variables
function _read_semver {
  export CI_NAME=$(if [ "$CIRCLE_BUILD_NUM" ]; then echo "circleci"; \
                      elif [ "$GITHUB_RUN_NUMBER" ]; then echo "githubaction"; \
                      else echo "local"; fi)

  export GIT_BRANCH=$(if [ "$CI_NAME" = "circleci" ]; then echo "$CIRCLE_BRANCH"; \
                      elif [ "$CI_NAME" = "githubaction" ]; then echo "$GITHUB_REF_NAME"; \
                      else echo "local"; fi)

  export GIT_TAG=$(if [ "$CI_NAME" = "circleci" ]; then echo "$CIRCLE_TAG"; \
                      elif [ "$CI_NAME" = "githubaction" ]; then \
                        if [ "$GITHUB_REF_TYPE" = "tag" ]; then \
                          echo "$GITHUB_REF_NAME"; \
                        else echo ""; fi \
                      else echo ""; fi)

  export BUILD_NUM=$(if [ "$CI_NAME" = "circleci" ]; then echo "$CIRCLE_BUILD_NUM"; \
                      elif [ "$CI_NAME" = "githubaction" ]; then echo "$GITHUB_RUN_NUMBER"; \
                      else echo "0"; fi)

  export SEMVER_NUMBER=$(if [ "$SEMVER_NUMBER" ]; then echo "$SEMVER_NUMBER"; \
                        else echo "0.0.1"; fi)

  # default
  #local DEFUALT_SEMVER_EDITION=${:-vika}
  export SEMVER_EDITION=${DEFUALT_SEMVER_EDITION:-vika}

  if [ -z "$GIT_TAG" ]; then
      # Release Branch
      # split git branch into   EDITION + SEMVER_NUMBER
      # etc.   release/1.0.0  ->    "abc" & "1.0.0"
      if [[ $GIT_BRANCH == *"/"* ]]; then
        arr=(${GIT_BRANCH//\// })

        local BRANCH_EDITION=${arr[0]}

        # special handle for non `release/`
        if [ "$BRANCH_EDITION" != "release" ]; then
          export SEMVER_EDITION=$BRANCH_EDITION
        fi

        export SEMVER_NUMBER=${arr[1]}
        export SEMVER_TYPE="beta"
      else
        export SEMVER_TYPE="alpha"
      fi

      # Git Branch
      export SEMVER_PRERELEASE=$SEMVER_TYPE
      export SEMVER="v$SEMVER_NUMBER-$SEMVER_TYPE"
  else
      local SEMVER_FROM_TAG=$GIT_TAG

      # split git tag into   EDITION + SEMVER_FROM_TAG
      # etc.   abc/v1.0.0-release  ->    "abc" & "v1.0.0-release"
      if [[ $GIT_TAG == *"/"* ]]; then
        arr=(${GIT_TAG//\// })

        export SEMVER_EDITION=${arr[0]}
        SEMVER_FROM_TAG=${arr[1]}
      fi

      # Git Tag
      export SEMVER_PRERELEASE=$(bash /tmp/semver get prerel $SEMVER_FROM_TAG)
      export SEMVER_TYPE=$SEMVER_PRERELEASE
      export SEMVER="$SEMVER_FROM_TAG"
  fi;

  export SEMVER_METADATA="$SEMVER_EDITION.build$BUILD_NUM"
  export SEMVER_FULL="$SEMVER+$SEMVER_METADATA"
}

# Build the Docker with Docker Image Name
function _build_docker {
  #By default, the success callback is automatically called
  manual_call_success=false

  #parse commandline options
  while getopts "n:m" arg; do
    case $arg in
    n)
      export DOCKER_IMAGE_NAME=$OPTARG
      echo "\$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_NAME"
      ;;
    m)
      manual_call_success=true
      echo "[WARNING] Need to call the method manually [_on_build_success]!"
      ;;
    ?)
      echo "unknown argument"
      exit 1
      ;;
    esac
  done

  if [[ -z "$DOCKER_IMAGE_NAME" ]]; then
    echo "[ERROR] Need Arugment#1 for \$DOCKER_IMAGE_NAME Define..."
    exit 1
  fi

  if [[ -z "${CR_PAT}" ]]; then
    echo "[WARNING] Need \$CR_PAT Github Package Personal Access Token Define..."
    read -p "Please enter CR_PAT: " CR_PAT
  else
    echo "Found \$CR_PAT. "
  fi

  # login
  echo $CR_PAT | docker login ghcr.io -u vikadata --password-stdin

  # tag list
  local target_tag_array=(${TARGET_DOCKER_TAGS:="latest" "latest-$SEMVER_TYPE" "$SEMVER" "build$BUILD_NUM" "${SEMVER}_build$BUILD_NUM"})

  # 使用buildx 构建多平台镜像
  if [[ "$MULTI_PLATFORM" == "true" ]]; then
    echo "Multi Platform Docker Building..."
    # install docker buildx environment
    docker run --rm --privileged tonistiigi/binfmt:latest --install all

    # create and use instances，ignore duplicate error warnings
    docker buildx create --use --name=builder-"$(uname -n)" --driver docker-container --driver-opt env.BUILDKIT_STEP_LOG_MAX_SIZE=-1 --driver-opt env.BUILDKIT_STEP_LOG_MAX_SPEED=-1 || true

    # 打包并推送多平台镜像
    _build_and_push_multiple_platform_docker "ghcr.io" "${target_tag_array[@]}"
    _build_and_push_multiple_platform_docker "docker.vika.ltd" "${target_tag_array[@]}"
  else
    echo "Docker Building..."
    TEMP_TAG_NAME="vikadata/$SEMVER_EDITION/$DOCKER_IMAGE_NAME:latest"
    # 构建第一个镜像
    docker build $BUILD_ARG --tag $TEMP_TAG_NAME . -f ${DOCKERFILE:=Dockerfile} || exit 1

    # 给镜像 tag and push
    _tag_and_push_docker "$TEMP_TAG_NAME" "ghcr.io" "${target_tag_array[@]}"
    _tag_and_push_docker "$TEMP_TAG_NAME" "docker.vika.ltd" "${target_tag_array[@]}"
  fi

  if ! $manual_call_success; then
    _on_build_success
  fi
}

# On Build Success Event
# Request to devops Github Action to Deploy Image
function _on_build_success {
   DOCKER_IMAGE=${DOCKER_IMAGE_NAME_FULL}:${DOCKER_IMAGE_TAG}_build${BUILD_NUM}
   echo "_on_build_success -> $DOCKER_IMAGE , SEMVER_FULL -> ${SEMVER_FULL}"
   curl --location --request POST 'https://api.github.com/repos/vikadata/devops/dispatches' \
        --header 'Authorization: token '${CR_PAT}'' \
        --header 'Accept: application/vnd.github.everest-preview+json' \
	--header 'Content-Type: application/json' \
	--data '{
    	"event_type": "deploy",
	    "client_payload":{
        	 "SEMVER_FULL":"'${SEMVER_FULL}'",
       		 "app": "'${DOCKER_IMAGE_NAME}'",
       		 "containerName": "'${DOCKER_IMAGE_NAME}'",
       		 "image": "'${DOCKER_IMAGE}'"
   		 }
	}'
}

function _tag_and_push_docker {
  local docker_registry="$2" # [REGISTRYHOST/][USERNAME/]NAME[:TAG]
  local source_image="$1"  # SOURCE_IMAGE[:TAG]
  shift 2
  local tags=("$@") # TARGET_IMAGE[:TAG] LIST

  DOCKER_IMAGE_NAME_FULL="$docker_registry/vikadata/$SEMVER_EDITION/$DOCKER_IMAGE_NAME"
  export DOCKER_IMAGE_TAG="$SEMVER"

  local full_docker_target
  for tag in "${tags[@]}"; do
    full_docker_target="$full_docker_target $DOCKER_IMAGE_NAME_FULL:$tag"
  done

  # login
  echo "$CR_PAT" | docker login "$docker_registry" -u vikadata --password-stdin
  # out
  echo "$full_docker_target" | xargs -n 1 echo || exit 1
  # tag
  echo "$full_docker_target" | xargs -n 1 docker tag "$source_image" || exit 1
  # push
  echo "$full_docker_target" | xargs -n 1 docker push || exit 1
  # Clean up the local, free up space
  echo "$full_docker_target" | xargs -n 1 docker rmi || exit 1
}

function _build_and_push_multiple_platform_docker {
  local docker_registry="$1" # [REGISTRYHOST/][USERNAME/]NAME[:TAG]
  shift
  local tags=("$@") # TARGET_IMAGE[:TAG] LIST

  DOCKER_IMAGE_NAME_FULL="$docker_registry/vikadata/$SEMVER_EDITION/$DOCKER_IMAGE_NAME"
  export DOCKER_IMAGE_TAG="$SEMVER"

  local full_docker_target
  for tag in "${tags[@]}"; do
    full_docker_target="$full_docker_target --tag $DOCKER_IMAGE_NAME_FULL:$tag"
  done

  # login
  echo "$CR_PAT" | docker login "$docker_registry" -u vikadata --password-stdin
  # out
  echo "$full_docker_target" | xargs -n 2 echo || exit 1
  # build and push
  docker buildx build $BUILD_ARG -f ${DOCKERFILE:=Dockerfile} --platform linux/arm64,linux/amd64 $full_docker_target . --push
}

function build_docker {
  env_dotversion
  _build_docker -n $1
}

function build_docker_dotversion {
  env_dotversion
  _build_docker -n $1
}
function build_docker_java {
  env_java
  _build_docker -n $1
}
function build_docker_nodejs {
  env_nodejs
  _build_docker -n $1
}
function build_docker_webserver {
  env_nodejs
  _build_docker -n $1
}
# Unable to confirm, the method of calling the "success callback" timing
# requires the caller to call the "success callback" at the appropriate timing
function build_docker_unableack {
  case "$1" in
  java) env_java ;;
  node) env_nodejs ;;
  dotversion) env_dotversion ;;
  *)
    echo "unknown env，support list: [java, node, dotversion]"
    exit 1
    ;;
  esac

  _build_docker -n "$2" -m
}

# assert equals
function assert_eq {
  local expected="$1"
  local actual="$2"
  local msg="${3-}"

  if [ "$expected" == "$actual" ]; then
    return 0
  else
    [ "${#msg}" -gt 0 ] && echo "$expected == $actual :: $msg" || true
    return 1
  fi
}

# print all export outputs variables
function exports_info {
  echo ""
  echo "[Information Exports]"

  echo "\$CI_NAME: $CI_NAME"
  echo "\$GIT_BRANCH: $GIT_BRANCH"
  echo "\$GIT_TAG: $GIT_TAG"
  echo "\$BUILD_NUM: $BUILD_NUM"
  echo "\$SEMVER: $SEMVER"
  echo "\$SEMVER_PRERELEASE: $SEMVER_PRERELEASE"
  echo "\$SEMVER_TYPE: $SEMVER_TYPE"
  echo "\$SEMVER_EDITION: $SEMVER_EDITION"
  echo "\$SEMVER_METADATA: $SEMVER_METADATA"
  echo "\$SEMVER_FULL: $SEMVER_FULL"
  echo ""
}

# testing
function _test {
  _test_github_action
  _test_release_branch
  _test_gitflow

  _test_alpha

  _test_tag_with_edition
  _test_tag_without_edition

  exports_info
}

function _test_release_branch {
  local CIRCLE_TAG=""
  local CIRCLE_BUILD_NUM=""

  local GITHUB_RUN_NUMBER=789
  local GITHUB_REF_NAME=release/1.2.3
  local GITHUB_REF_TYPE="branch"

  _read_semver

  assert_eq $GIT_TAG "" "ERROR_GITTAG"
  assert_eq $CI_NAME "githubaction" "ERROR"
  assert_eq $BUILD_NUM 789 "ERROR"
  assert_eq $SEMVER_EDITION "vika" "ERROR_EDITION"

  local GITHUB_RUN_NUMBER=788
  local GITHUB_REF_NAME=customers/1.2.3

  _read_semver

  assert_eq $GIT_TAG "" "ERROR_GITTAG"
  assert_eq $CI_NAME "githubaction" "ERROR"
  assert_eq $BUILD_NUM 788 "ERROR"
  assert_eq $SEMVER_EDITION "customers" "ERROR"
}
function _test_gitflow {
  local SEMVER_NUMBER=7.0.8
  local CIRCLE_BUILD_NUM=123
  local CIRCLE_BRANCH=develop
  local BUILD_NUM=1234 # non sense
  local GIT_TAG=""

  _read_semver

  assert_eq $SEMVER v7.0.8-alpha "ERROR"
  assert_eq $SEMVER_FULL v7.0.8-alpha+vika.build123 "ERROR"
  assert_eq $SEMVER_PRERELEASE alpha "ERROR"
  assert_eq $CI_NAME "circleci" "ERROR"

}


function _test_github_action() {

  local GITHUB_RUN_NUMBER=321
  local GITHUB_REF_NAME=develop

  _read_semver

  assert_eq $CI_NAME "githubaction" "ERROR"
  assert_eq $BUILD_NUM 321 "ERROR"

}

# function _test_drone_ci {
#   assert_eq $CI_NAME "drone" "ERROR"
#   assert_eq $BUILD_NUM 321 "ERROR"
# }

function _test_alpha {
  local SEMVER_NUMBER=1.0.3
  local CIRCLE_BRANCH=integration
  local CIRCLE_BUILD_NUM=1234
  local GIT_TAG=""

  _read_semver

  assert_eq $CI_NAME "circleci" "ERROR"
  assert_eq $SEMVER v1.0.3-alpha "ERROR"
  assert_eq $SEMVER_FULL v1.0.3-alpha+vika.build1234 "ERROR"
  assert_eq $SEMVER_PRERELEASE alpha "ERROR"

}

function _test_tag_with_edition {
  # sim Circle CI
  local CIRCLE_BUILD_NUM=4321
  # if tag with EDITION
  local CIRCLE_TAG="vika-op/v2.0.1-release.2"

  _read_semver
  assert_eq $CI_NAME "circleci"
  assert_eq $SEMVER v2.0.1-release.2 "ERROR"
  assert_eq $SEMVER_FULL v2.0.1-release.2+vika-op.build4321 "ERROR"
  assert_eq $SEMVER_PRERELEASE release.2 "ERROR"
  assert_eq $SEMVER_EDITION vika-op "ERROR"


}

function _test_tag_without_edition {
  # if TAG without EDITION
  local CIRCLE_BUILD_NUM=3333
  local CIRCLE_TAG=apitable/v3.0.1-release.2

  _read_semver
  assert_eq $SEMVER v3.0.1-release.2 "ERROR"
  assert_eq $SEMVER_FULL v3.0.1-release.2+apitable.build3333 "ERROR"
  assert_eq $SEMVER_PRERELEASE release.2 "ERROR"

}

function _test_build_docker_dotversion {
  local APP=webhook-server
  build_docker_dotversion $APP
}
