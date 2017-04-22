FROM tristansalles/usyd-uos-geos-ocean-base:latest

MAINTAINER Tristan Salles

#RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
#    python-imaging

RUN pip install cmocean

# Install XBEACH model
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    automake \
    autoconf \
    libtool \
    shtool \
    autogen \
    svn

RUN cd /usr/local && \
    svn checkout https://svn.oss.deltares.nl/repos/xbeach/trunk && \
    cd trunk && \
    sh autogen.sh && \
    ./configure --with-netcdf && \
    make && \
    make install

# Get debian base install and some unnecessary files, copy local data to workspace
RUN mkdir /workspace && \
    mkdir /workspace/volume

# Copy local directory to image
COPY UoS /workspace

# expose notebook port
EXPOSE 8888

# setup space for working in
VOLUME /workspace/volume

# launch notebook
WORKDIR /workspace
EXPOSE 8888
ENTRYPOINT ["/usr/local/bin/tini", "--"]

CMD jupyter notebook --ip=0.0.0.0 --no-browser \
    --NotebookApp.default_url='/tree/StartHere.ipynb'
