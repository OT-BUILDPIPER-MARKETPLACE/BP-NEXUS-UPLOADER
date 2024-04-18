# BP-SHELL-STEP-TEMPLATE
I'll <do xyz>

## Setup
* Clone the code available at [BP-SHELL-STEP-TEMPLATE](https://github.com/OT-BUILDPIPER-MARKETPLACE/BP-SHELL-STEP-TEMPLATE)

* Build the docker image
```
git submodule init
git submodule update
docker build -t ot/push_artifact:0.1 .
```

* Do local testing
```
docker run -it --rm -v $PWD:/src -e WORKSPACE=/src -e BUILD_NUMBER="" -e BUILD_COMPONENT_NAME="BUILD_COMPONENT_NAME" -e ARTIFACT="" -e USERNAME="" -e PASSWORD="" -e NEXUS_URL="" -e REPO_NAME="" ot/push_artifact:0.1
```

* Debug
```
docker run -it --rm -v $PWD:/src -e WORKSPACE=/src -e BUILD_NUMBER="" -e BUILD_COMPONENT_NAME="BUILD_COMPONENT_NAME" -e ARTIFACT="" -e USERNAME="" -e PASSWORD="" -e NEXUS_URL="" -e REPO_NAME="" --entrypoint sh ot/push_artifact:0.1
```