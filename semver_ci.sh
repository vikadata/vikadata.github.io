
# This script get Vika SemVer from Circle CI Environment Variables
# Author: Kelly Peilin Chan<kelly@vikadata.com>
# Created: 2022-05-17
# Modified: 2022-05-20

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

  local GIT_BRANCH=$CIRCLE_BRANCH
  local GIT_TAG=$CIRCLE_TAG
  local BUILD_NUM=$CIRCLE_BUILD_NUM

  if [ -z "$SEMVER_EDITION" ]; then
    # default
    export SEMVER_EDITION="vika"
  fi;

  if [ -z "$GIT_TAG" ]; then
      # Git Branch
      export SEMVER_TYPE=$(if [ "$GIT_BRANCH" = "integration" ]; then echo "alpha"; elif [ "$GIT_BRANCH" = "staging" ]; then echo "beta"; else echo $GIT_BRANCH ; fi)
      export SEMVER_PRERELEASE=$SEMVER_TYPE
      export SEMVER="v$SEMVER_NUMBER-$SEMVER_TYPE"
      export DEPLOY_ENV=$CIRCLE_BRANCH
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
      export DEPLOY_ENV="production"
  fi;

  export SEMVER_METADATA="$SEMVER_EDITION.build$BUILD_NUM"
  export SEMVER_FULL="$SEMVER+$SEMVER_METADATA"
}

# Build the Docker with Docker Image Name
function build_docker {
  if [[ -z "$1" ]]; then
    echo "[ERROR] Need Arugment#1 for \$DOCKER_IMAGE_NAME Define..."
    exit 1
  else
    export DOCKER_IMAGE_NAME=$1
    echo "\$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_NAME"

  fi

  if [[ -z "${CR_PAT}" ]]; then
    echo "[ERROR] Need \$CR_PAT Github Package Personal Access Token Define..."
    exit 1
  else
    echo "Found \$CR_PAT. "
  fi

  # staging 构建多平台镜像
  if [[ "$CIRCLE_BRANCH" = "staging" ]]; then
    # 准备 docker buildx
    docker run --rm --privileged tonistiigi/binfmt:latest --install all

    docker context create buildx-build
    docker buildx create --use buildx-build

    # 打包并推送多平台镜像
    _build_and_push_multiple_platform_docker "ghcr.io"
    _build_and_push_multiple_platform_docker "docker.vika.ltd"
  else
    TEMP_TAG_NAME="vikadata/$SEMVER_EDITION/$DOCKER_IMAGE_NAME:latest"
    # 构建第一个镜像
    docker build --tag $TEMP_TAG_NAME . -f ${DOCKERFILE:=Dockerfile} || exit 1

    # 给镜像打 tag
    _tag_and_push_docker "ghcr.io" $TEMP_TAG_NAME
    _tag_and_push_docker "docker.vika.ltd" $TEMP_TAG_NAME
  fi

  _on_build_success
  _on_build_success_apitable
}


# On Build Success Event
# Request to devops Github Action to Deploy Image 
function _on_build_success {
   DOCKER_IMAGE=${DOCKER_IMAGE_NAME_FULL}:${DOCKER_IMAGE_TAG}_build${CIRCLE_BUILD_NUM}
   echo "_on_build_success -> $DOCKER_IMAGE"
   curl --location --request POST 'https://api.github.com/repos/vikadata/devops/dispatches' \
        --header 'Authorization: token '${CR_PAT}'' \
        --header 'Accept: application/vnd.github.everest-preview+json' \
	--header 'Content-Type: application/json' \
	--data '{
    	"event_type": "deploy",
	    "client_payload":{
        	"edition":"vika",
       		 "env": "'${DEPLOY_ENV}'",
       		 "app": "'${DOCKER_IMAGE_NAME}'",
       		 "containerName": "'${DOCKER_IMAGE_NAME}'",
       		 "image": "'${DOCKER_IMAGE}'"
   		 }
	}'
}

# On Build Success Event
# Request to devops Github Action to Deploy Image 
function _on_build_success_apitable {
   DOCKER_IMAGE=${DOCKER_IMAGE_NAME_FULL}:${DOCKER_IMAGE_TAG}_build${CIRCLE_BUILD_NUM}
   echo "_on_build_success_apitable -> $DOCKER_IMAGE"
   curl --location --request POST 'https://api.github.com/repos/vikadata/devops/dispatches' \
        --header 'Authorization: token '${CR_PAT}'' \
        --header 'Accept: application/vnd.github.everest-preview+json' \
	--header 'Content-Type: application/json' \
	--data '{
    	"event_type": "deploy",
	    "client_payload":{
        	"edition":"apitable",
       		 "env": "'${DEPLOY_ENV}'",
       		 "app": "'${DOCKER_IMAGE_NAME}'",
       		 "containerName": "'${DOCKER_IMAGE_NAME}'",
       		 "image": "'${DOCKER_IMAGE}'"
   		 }
	}'
}

function _tag_and_push_docker {
  DOCKER_REGISTRY=$1
  TEMP_TAG_NAME=$2
  DOCKER_IMAGE_NAME_FULL="$DOCKER_REGISTRY/vikadata/$SEMVER_EDITION/$DOCKER_IMAGE_NAME"

  export DOCKER_IMAGE_TAG="$SEMVER"

  echo $CR_PAT | docker login $DOCKER_REGISTRY -u vikadata --password-stdin

  # docker pull "$DOCKER_IMAGE_NAME_FULL:latest-$SEMVER_TYPE" || true
  docker tag $TEMP_TAG_NAME "$DOCKER_IMAGE_NAME_FULL:latest-$SEMVER_TYPE" || exit 1
  docker tag $TEMP_TAG_NAME "$DOCKER_IMAGE_NAME_FULL:$DOCKER_IMAGE_TAG" || exit 1
  docker tag $TEMP_TAG_NAME "$DOCKER_IMAGE_NAME_FULL:latest" || exit 1
  docker tag $TEMP_TAG_NAME "$DOCKER_IMAGE_NAME_FULL:build$CIRCLE_BUILD_NUM" || exit 1
  docker tag $TEMP_TAG_NAME "$DOCKER_IMAGE_NAME_FULL:${DOCKER_IMAGE_TAG}_build$CIRCLE_BUILD_NUM" || exit 1

  docker push "$DOCKER_IMAGE_NAME_FULL:latest-$SEMVER_TYPE"  || exit 1
  docker push "$DOCKER_IMAGE_NAME_FULL:$DOCKER_IMAGE_TAG"  || exit 1
  docker push "$DOCKER_IMAGE_NAME_FULL:latest"  || exit 1
  docker push "$DOCKER_IMAGE_NAME_FULL:build$CIRCLE_BUILD_NUM"  || exit 1
  docker push "$DOCKER_IMAGE_NAME_FULL:${DOCKER_IMAGE_TAG}_build$CIRCLE_BUILD_NUM"  || exit 1
}

function _build_and_push_multiple_platform_docker {
  DOCKER_REGISTRY=$1

  DOCKER_IMAGE_NAME_FULL="$DOCKER_REGISTRY/vikadata/$SEMVER_EDITION/$DOCKER_IMAGE_NAME"

  export DOCKER_IMAGE_TAG="$SEMVER"

  echo $CR_PAT | docker login $DOCKER_REGISTRY -u vikadata --password-stdin

  local TAG1="$DOCKER_IMAGE_NAME_FULL:latest-$SEMVER_TYPE"
  local TAG2="$DOCKER_IMAGE_NAME_FULL:$DOCKER_IMAGE_TAG"
  local TAG3="$DOCKER_IMAGE_NAME_FULL:latest"
  local TAG4="$DOCKER_IMAGE_NAME_FULL:build$CIRCLE_BUILD_NUM"
  local TAG5="$DOCKER_IMAGE_NAME_FULL:${DOCKER_IMAGE_TAG}_build$CIRCLE_BUILD_NUM"

  docker buildx build -f ${DOCKERFILE:=Dockerfile} --platform linux/arm64,linux/amd64 --tag $TAG1 --tag $TAG2 --tag $TAG3 --tag $TAG4 --tag $TAG5 . --push
}

function build_docker_dotversion {
  env_dotversion
  build_docker $1
}
function build_docker_java {
  env_java
  build_docker $1
}
function build_docker_nodejs {
  env_nodejs
  build_docker $1
}
function build_docker_webserver {
  env_nodejs
  build_docker $1
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
  echo "\$SEMVER: $SEMVER"
  echo "\$SEMVER_PRERELEASE: $SEMVER_PRERELEASE"
  echo "\$SEMVER_TYPE: $SEMVER_TYPE"
  echo "\$SEMVER_EDITION: $SEMVER_EDITION"
  echo "\$SEMVER_METADATA: $SEMVER_METADATA"
  echo "\$SEMVER_FULL: $SEMVER_FULL"
}

# testing
function _test {
  _test_alpha

  _test_tag_with_edition
  _test_tag_without_edition

}

function _test_alpha {
  local SEMVER_NUMBER=1.0.3
  local CIRCLE_BRANCH=integration
  local CIRCLE_BUILD_NUM=1234
  local CIRCLE_TAG=""
  local SEMVER_EDITION="vika"
  
  _read_semver 
  assert_eq $SEMVER v1.0.3-alpha "ERROR"
  assert_eq $SEMVER_FULL v1.0.3-alpha+vika.build1234 "ERROR"
  assert_eq $SEMVER_PRERELEASE alpha "ERROR"

  exports_info
}

function _test_tag_with_edition {
  local CIRCLE_BUILD_NUM=4321
  # if tag with EDITION
  local CIRCLE_TAG="vika-op/v2.0.1-release.2"
  _read_semver 
  assert_eq $SEMVER v2.0.1-release.2 "ERROR"
  assert_eq $SEMVER_FULL v2.0.1-release.2+vika-op.build4321 "ERROR"
  assert_eq $SEMVER_PRERELEASE release.2 "ERROR"
  assert_eq $SEMVER_EDITION vika-op "ERROR"

  exports_info

}

function _test_tag_without_edition {
  # if TAG without EDITION
  local CIRCLE_BUILD_NUM=3333
  local CIRCLE_TAG=v3.0.1-release.2
  local SEMVER_EDITION="apitable"
  _read_semver 
  assert_eq $SEMVER v3.0.1-release.2 "ERROR"
  assert_eq $SEMVER_FULL v3.0.1-release.2+apitable.build3333 "ERROR"
  assert_eq $SEMVER_PRERELEASE release.2 "ERROR"

  exports_info
}

function _test_build_docker_dotversion {
 local APP=webhook-server
 build_docker_dotversion $APP
}
