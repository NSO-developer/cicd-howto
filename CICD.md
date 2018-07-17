# Implementing GitLab for NSO

## Introduction

This guide will give an example of how a Continuous Integration / Continuous Deployment (CICD) environment can be implemented for an NSO function pack project using GitLab. We set this up using Docker containers, allowing for flexible deployment and easy upgrades. If you are not familiar with Docker and containers in general, you can read a little bit about them on the [Docker website](https://www.docker.com/what-container).

[GitLab](https://gitlab.com) is a reasonably complete DevOps environment. It can be used in all stages of the DevOps cycle. It can handle sprint planning, source code control, test, deployment and issue tracking. It is an excellent starting point for this guide since it makes it easy to get started without setting up multiple separate systems.

What we present here is not a tutorial on GitLab, but rather an example of how to customize GitLab for our needs, nor is is a tutorial on CICD, DevOps or NSO. It is simply a guide on how to set up a system that is a good starting point for developing your package with NSO. We will start with a minimal running example and then move on to a slightly more realistic example.

We will assume that you have a basic understanding of NSO, it is also helpful if you have a basic understanding of git, if not there are many [tutorials online](https://www.atlassian.com/git/tutorials) that provide a good introduction.

This repository is stored in [git](https://github.com/NSO-developer/cicd-howto), and some of the examples below can be found in that repository, or inline in this document.

# Preparation

You will need a server to run GitLab, as well as possibly a number of additional machines to serve as *runners* to enable clean and concurrent runs of the CICD pipelines. You will want to make sure that these hosts are included in your backup routines. 

In preparing this guide we used a freshly installed Linux machine running Ubuntu Server 16.04, and the commands reflect that. We used a single VM with 16 vCPUs and 64 GB of memory, resources are needed mostly for running the runners and a minimal install would probably be 4vCPUs and 16GB of memory.

## Setup of the Linux machine

First setup the basic setup, including backup and users on the system. Your system will need internet access to download software, but if desired it can be through NAT or a proxy, take this into account when setting up the system.

You will need a disk to store persistent data, we will use the `/srv` directory tree. We will use it to store both GitLab data and artifacts for NSO, it is crucial to back up this directory.

You will have to install basic development tools, as well as the Docker package on the system:
```
apt-get update
apt-get dist-upgrade -y
apt-get install gcc make binutils python docker.io
```

## Copy NSO to the machine

Create the directory `/srv/store` on the machine and place your NSO distribution there together with any NEDs:
```
root@ubuntu:~# mkdir -p /srv/store
root@ubuntu:~# cp nso-4.7.linux.x86_64.installer.bin /srv/store/
```

# Install GitLab

We will be using the community edition (GitLab CE) rather than the enterprise edition (GitLab EE) - if you have a commercial license for GitLab EE, use that instead, the steps will be very similar except that the name of the Docker image is gitlab-ee instead of gitlab-ce. Full installation instructions are available [online](https://docs.gitlab.com/omnibus/docker/).

We will publish http and https from GitLab on their regular ports, but will publish the ssh port on 22022, we will also set the container to restart automatically, and to store persistent data in `/srv/gitlab`, modify your hostname as appropriate (throughout this guide we will assume that `gitlab.example.com` resolves to your GitLab host):

```
docker run --detach \
    --hostname gitlab.example.com \
    --publish 443:443 --publish 80:80 --publish 22022:22 \
    --name gitlab \
    --restart always \
    --volume /srv/gitlab/config:/etc/gitlab \
    --volume /srv/gitlab/logs:/var/log/gitlab \
    --volume /srv/gitlab/data:/var/opt/gitlab \
    gitlab/gitlab-ce:latest
```

This will automatically fetch the latest GitLab image from the internet. If you want to update GitLab at a later stage you can run `docker pull gitlab/gitlab-ce:latest` to fetch the latest from the repository, and then use `docker restart gitlab` to restart the container.

It will take a few minutes for GitLab to startup fully, you can use `docker ps` to check the status on your container, the desired state is something like `Up 4 minutes (healthy)`. You can then navigate to the machine using HTTP. The first time you have to set an admin password for the user `root`.

You can set up additional users with permissions as required, also make sure to [add your ssh-key to the GitLab server](https://www.packtpub.com/mapt/book/application_development/9781783986842/2/ch02lvl1sec20/adding-your-ssh-key-to-gitlab). 


## Changing the configuration

Since we are publishing the ssh port on port 22022, we will have to update the GitLab config. Edit the file `/srv/gitlab/config/gitlab.rb` and change the line
```
# gitlab_rails['gitlab_shell_ssh_port'] = 22
```
to
```
gitlab_rails['gitlab_shell_ssh_port'] = 22022
```

Depending on if you have working DNS in your lab or not, you may also want to set `external_url` to your ip-address:
```
external_url 'http://<IP-ADDRESS>' 
```

If you had to do this, you probably also have to replace 'gitlab.example.com' with your ip-address in the rest of this document.

You will have to run `docker restart gitlab` to make sure the change sticks.

## Setting up a project

As a demonstration we will put the example project `4-rfs-service` from the NSO distribution into your system, but the same general procedure can be used for any project.

## Setup the empty project in GitLab

First create a group, to group all of your NSO related repositories together. Click *Create a Group* in the main GitLab user interface, we will use the name 'nso'. You can use groups to share things like access rules.

Then create a project in that group by pressing *new project*, we will call our project `rfs-service`. We are now ready to add some files. Either on the Linux machine or on your development machine where you have NSO installed:

1. Clone the empty repository
```
git clone ssh://git@gitlab.example.com:22022/nso/rfs-service.git
```

2. Copy the example into the repository and commit it
```
cp -Rp ${NCS_DIR}/examples.ncs/getting-started/developing-with-ncs/4-rfs-service/* .
git add .
git commit -m "Initial import"
git push
```

These commands put all of the files into GitLab, and you can now look at them in the [GitLab web interface](http://gitlab.example.com/nso/rfs-service). 

3. Make sure that it builds cleanly
```
make
```


# Setting up a simple CICD

We can now set up a simple test to make sure that it builds. To do this we need first to create one or more *runners* for GitLab, and then create a Docker image that we can use to run our build and test process.

## Create a local registry


Since we want to create our own Docker images, we also create a local Docker registry:

```
docker run -d -p 5000:5000 --restart=always --name registry registry:2
```

This allows us to locally create, save and store Docker images. If you already have an internal image registry, you can use that instead. Optionally, you can enable [the container registry in GitLab](https://docs.gitlab.com/ee/user/project/container_registry.html) and use that.

## Create a base container suitable for NSO-related tasks

Containers are created using something called a `Dockerfile`. There are several recommendations online on how to optimize Dockerfiles, e.g. by using multi-stage builds. It's not the aim of this guide to provide the most optimized Dockerfiles, but rather something that's easy to read.

Create a directory called [`nso-base`](docker/nso-base) and create the following `Dockerfile` in that directory:
```dockerfile
# NSO base image
FROM ubuntu:18.10

ARG NSOVER

WORKDIR /app

# Install packages
RUN apt-get update -qq && \
    apt-get install -qq apt-utils openssh-client default-jdk-headless python && \
    apt-get -qq clean autoclean && \
    apt-get -qq autoremove 

# Install NSO
COPY nso-$NSOVER.linux.x86_64.installer.bin .
RUN sh nso-$NSOVER.linux.x86_64.installer.bin /app/nso && \
    rm nso-$NSOVER.linux.x86_64.installer.bin

# Setup basic ssh config
RUN mkdir /root/.ssh && chmod 700 /root/.ssh
COPY config /root/.ssh
```

Also make sure to copy your NSO binary into the directory so the Docker file can use it:
```
cp /srv/store/nso-4.7.linux.x86_64.installer.bin .
```

In that directory also create a file named `config` with the following contents:
```
StrictHostKeyChecking no
```

You can then build you Docker container and push it to the Docker repository with the following command:
```
docker build --build-arg NSOVER=4.7 -t nso-base .
docker tag nso-base gitlab.example.com:5000/nso-base
docker push gitlab.example.com:5000/nso-base
```


## Create an image suitable for running some basic tests

We want to create an image we call `cicd-runner`, which is built on top of the `nso-base` image.  Like before, create a directory called [`cicd-runner`](docker/cicd-runner), and create a file named `Dockerfile` in it with the following content:
```dockerfile
FROM nso-base

# Add CICD packages
RUN apt-get install -qq git make ant libxml2-utils xsltproc
```

Then similarly build and push the image:
```
docker build -t cicd-runner .
docker tag cicd-runner gitlab.example.com:5000/cicd-runner
docker push gitlab.example.com:5000/cicd-runner
```

You now have a container that contains NSO as well as build tools and is suitable to use for tests. 

### Creating a runner

The simplest way to create one is to start a Docker container-based runner on your local machine:
```
docker run -d --name gitlab-runner-1 --restart always \
   -v /srv/gitlab-runner-dock/config:/etc/gitlab-runner \
   -v /var/run/docker.sock:/var/run/docker.sock   gitlab/gitlab-runner:latest
```

For production deployments you will want multiple runners, on many different machines. You can read more about runners in the [documentation](https://docs.gitlab.com/runner/register/index.html).

We then need to register this runner with GitLab. You need the registration-token, it can be found by going to [the runner page](http://gitlab.example.com/admin/runners) and looking for the text *Use the following registration token during setup*. 

1. Enter the runner
```
docker exec -ti gitlab-runner-1 /bin/bash
```

2. Register the runner using the following command with <TOKEN> replaced by the token you found above:
```
gitlab-runner register -n \
  --url http://gitlab.example.com/ \
  --registration-token <TOKEN> \
  --executor docker \
  --description "My Runner" \
  --docker-image "localhost:5000/cicd-runner"
```

Look for a text saying `Runner registered successfully`. You can now see your runner in the GitLab runners screen.

## Setting up your repository for CICD

In GitLab the CICD flow is controlled by the file [.gitlab_ci.yml](https://docs.gitlab.com/ee/ci/yaml/). It allows you to setup multiple stages of your job. Let us start with the most straightforward pipeline possible, with a single build step.


In your `rfs-service` directory, add a [`.gitlab-ci.yml`](ci/gitlab-ci1.yml) file with the following contents:
```yaml
before_script:
  # Get NSO initialized
  - source /app/nso/ncsrc

build:
  stage: build
  script:
    - make
```

Then commit and push this to GitLab:
```
git add .gitlab-ci.yml
git commit -m "Adding CI pipeline"
git push
```

You can then look at your pipelines in the [GitLab CI view](http://gitlab.example.com/nso/rfs-service/pipelines), where the job should succeed.

This concludes the first part of this guide, take this opportunity to look around in GitLab and familiarize yourself with the settings.


# Adding a simple test case

Next we might want to add a test case as well, to make sure that the package does something useful. There are many frameworks for writing test cases, but for this case we will write a simple shell script that we call [`test.sh`](ci/test.sh), which tests that nso starts and that you can show packages:
```bash
#!/bin/bash
ncs || exit 1
echo "show packages" | ncs_cli -u admin
exit $?
```

You then add a test stage to [`.gitlab-ci.yml`](ci/gitlab-ci2.yml):
```yaml
before_script:
  # Get NSO initialized
  - source /app/nso/ncsrc

build:
  stage: build
  script:
    - make

test:
  script:
    - make
    - ./test.sh    
```

Add, commit and push the updates:
```
chmod a+x test.sh
git add test.sh .gitlab-ci.yml
git commit -m "Updated CI pipeline with test case"
git push
```

Then go into the GitLab web interface to check the test results.

Note that if you want you can add multiple test stages, they will then be executed in parallel if possible, this allows you to use additional resources to speed up the tests.


# Building releases

You might have noticed in the previous chapter that the test stage also contained the `make` command. This seems like needless duplication and this is because by default GitLab does not copy any data between steps in the process, but we can instruct it to do so.

## Creating artifacts 

Data of value is referred to as [artifacts](https://docs.gitlab.com/ee/user/project/pipelines/job_artifacts.html). Let us add a new target to the [`Makefile`](ci/Makefile) that builds release packages, replace the original `Makefile` with this contents (observe that indented lines **must** start with tabs so pasting will not work):
```makefile
all:
  for f in packages/*/src; do \
    $(MAKE) -C $$f all || exit 1; \
  done
  $(MAKE) netsim

netsim:
  ncs-netsim create-network ./packages/router 3 ex --dir ./netsim

release: all
  mkdir -p release
  for f in packages/*; do \
    hash=`git rev-parse --short HEAD`;\
    tar cfz release/`basename $$f`-$$hash.tgz --exclude=src -C packages `basename $$f`;\
  done

clean:
  for f in packages/*/src; do \
    $(MAKE) -C $$f clean || exit 1; \
  done
  rm -rf packages/s1
  rm -rf ./netsim logs/* state/* ncs-cdb/*.cdb
  rm -rf release
```

Lets then change the build step to instead run `make release` in `.gitlab-ci.yml`, and make sure the releases are saved as artifacts, the new contents of [`.gitlab-ci.yml`](ci/gitlab-ci3.yml) will then be:
```yaml
before_script:
  # Get NSO initialized
  - source /app/nso/ncsrc

build:
  stage: build
  script:
    - make release
  artifacts:
    paths:
      - release/

test:
  script:
    - make
    - ./test.sh
```

You can now commit and push this (this is the last time we will explicitly show these commands, in the future follow this pattern):
```
git add Makefile .gitlab-ci.yml 
git commit -m "Adding artifact building"
git push
```

This will start another pipeline, now if you click on the result of a build step you will be given the option to "download artifacts", which will allow you to download the files for use on another system.


## Using artifacts in the test case 

Now, we want to use these artifacts in the test case. GitLab automatically copies over the artifacts produced in one step of the pipeline to the next, so we do not have to do that. However, how do we make sure that the release is used instead of the source packages?

In a more realistic system, we would run our test case in a sub-directory, but for simplicity we will move the directories around a little bit (this does no harm, since the result is discarded anyhow). So, we update [`.gitlab-ci.yml`](ci/gitlab-ci4.yml) again to remove make from the test step and add the moving of the directory so it looks like this:
```yaml
before_script:
  # Get NSO initialized
  - source /app/nso/ncsrc

build:
  stage: build
  script:
    - make release
  artifacts:
    paths:
      - release/

test:
  script:
    - mv packages packages.old
    - mv release packages
    - ./test.sh
```

This uses the pre-built packages instead of triggering a rebuild in the test stage. This can both speed up the execution of the chain and ensure that all steps are executed with exactly the same packages.


**TODO:** Continue here:

  - Using pre-built NEDs / storing data externally
  - Deployment
