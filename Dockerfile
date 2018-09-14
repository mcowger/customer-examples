FROM centos:7
RUN yum -y install awscli


ENTRYPOINT [ "/bin/sleep","1000" ]