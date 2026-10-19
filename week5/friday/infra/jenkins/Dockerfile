# Jenkins controller with the Docker CLI and a fixed plugin set.
FROM docker:27.5.1-cli AS dockercli

FROM jenkins/jenkins:2.580.1-lts-jdk21
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
