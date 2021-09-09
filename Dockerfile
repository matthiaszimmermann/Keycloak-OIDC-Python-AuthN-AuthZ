FROM phusion/baseimage:focal-1.0.0

RUN rm /bin/sh && ln -s /bin/bash /bin/sh && \
    sed -i 's/^mesg n$/tty -s \&\& mesg n/g' /root/.profile

WORKDIR /app

ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

# install additional packages
RUN apt-get update && apt-get install -y \
    git \
    tree \
    python3-pip

COPY requirements.txt /app

RUN pip3 install --no-cache-dir -r requirements.txt

# clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 5000


