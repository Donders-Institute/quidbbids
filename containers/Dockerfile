# syntax=docker/dockerfile:1
#
# QuIDBBIDS container based on full MATLAB, serving two use cases from one image:
#   - licensed: an interactive full MATLAB, e.g.
#       docker run --rm -it -e MLM_LICENSE_FILE=27000@your-license-server --entrypoint matlab quidbbids:v1.0.0
#   - license-free: the default ENTRYPOINT runs the mcc-compiled standalone app; the MATLAB installation acts
#     as the runtime root (a MATLAB installation can replace the MATLAB Runtime), so no license is needed
#
# Run mode examples:
#   1. full MATLAB (licensed): opens a MATLAB command terminal; proceed as on your desktop
#      (docs/GUI.rst, docs/CLI.rst). Add X11 forwarding for the GUI:
#      docker run --rm -it -e DISPLAY=$DISPLAY -e MLM_LICENSE_FILE=27000@your-license-server \
#          -v /tmp/.X11-unix:/tmp/.X11-unix -v /data/bids:/data/bids --entrypoint matlab quidbbids:v1.0.0
#   2a. compiled app, GUI (license-free, X11 forwarding; folder picker per docs/GUI.rst):
#       docker run --rm -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix -v /data/bids:/data/bids quidbbids:v1.0.0
#   2b. compiled app, CLI (license-free):
#       docker run --rm -v /data/bids:/data/bids quidbbids:v1.0.0 --bidsdir /data/bids \
#           --deliverables MWFmap,Chimap --configfile /data/bids/code/quidbbids_config.json
#
# Build (compiling with mcc needs a MATLAB license at build time):
# NB: Packages in containers/sepia/external are included as SEPIA dependencies (typically: 'segue' and 'mrisc')
#   docker build -t quidbbids:v1.0.0 -f containers/Dockerfile . --build-arg MCR_TAG=r2026a \
#       --build-arg MLM_LICENSE_FILE=27000@your-license-server
#
# GPU workers (MCR_GPUWorker/R1R2starWorker): add --gpus all (NVIDIA container runtime); if CUDA libraries are
#   missing, switch the base image to mathworks/matlab-deep-learning:${MCR_TAG}

ARG MCR_TAG=r2026a
ARG MLM_LICENSE_FILE=""
ARG SYNTHSTRIP_IMAGE=freesurfer/synthstrip:latest    # GPU nodes: freesurfer/synthstrip:latest-gpu

# ---- SynthStrip stage: mri_synthstrip (brain extraction) from the official SynthStrip image ----
FROM ${SYNTHSTRIP_IMAGE} AS synthstrip

# ---- main image: full MATLAB + compiled app + external tools ----
FROM mathworks/matlab:${MCR_TAG}
ARG MLM_LICENSE_FILE
ENV MLM_LICENSE_FILE=${MLM_LICENSE_FILE} FREESURFER_HOME=/freesurfer PATH=/freesurfer:${PATH}
ENV PYTHONUSERBASE=/freesurfer/env
ENV SEPIA_TOOLBOXES=/opt/quidbbids/dependencies/sepia/external
ENV DEPS=/opt/quidbbids/dependencies

# ---- 1. Clone QuIDBBIDS (the MATLAB dependencies come along as git submodules) ----
RUN apt-get update && apt-get install -y --no-install-recommends git fonts-noto-color-emoji fonts-noto-core \
    && git clone --recurse-submodules --depth 1 https://github.com/Donders-Institute/quidbbids.git /opt/quidbbids

# SEPIA's external toolboxes from the build context (repo root); moved into place in section 2
COPY containers/sepia/external/ /opt/sepia-external/

# ---- 2. SEPIA: place its external toolboxes and point SpecifyToolboxesDirectory.m at them ----
# Tensor-MP-PCA (denoising add-on) is not a _HOME var; SEPIA looks for it at SEPIA_HOME/external/Tensor-MP-PCA
RUN mv /opt/sepia-external $DEPS/sepia/external \
    && cp $DEPS/sepia/SpecifyToolboxesDirectory.template.m $DEPS/sepia/SpecifyToolboxesDirectory.m \
    && sed -i -e "s|/path/to|$DEPS/sepia/external|g" \
              -e "s|MEDI_HOME *= .*|MEDI_HOME = '$DEPS/MEDI_toolbox/';|" \
              -e "s|MRITOOLS_HOME *= .*|MRITOOLS_HOME = '$DEPS/sepia/external/mritools/';|" \
              $DEPS/sepia/SpecifyToolboxesDirectory.m \
    && ln -s $DEPS/Tensor-MP-PCA $DEPS/sepia/external/Tensor-MP-PCA

# ---- 3. CompileMRI's prebuilt mritools bundle (ROMEO, CLEAR-SWI, ...); MRITOOLS_HOME points here ----
ARG COMPILEMRI_VERSION=4.9.1
RUN wget -q "https://github.com/korbinian90/CompileMRI.jl/releases/download/v${COMPILEMRI_VERSION}/"\
"mritools_linux_x64_${COMPILEMRI_VERSION}.tar.gz" -O /tmp/mritools.tar.gz \
    && mkdir -p $DEPS/sepia/external/mritools \
    && tar -xzf /tmp/mritools.tar.gz -C $DEPS/sepia/external/mritools --strip-components=1 \
    && rm /tmp/mritools.tar.gz

# ---- 4. Compile the standalone app with mcc ----
# -a bundles +qb, dependencies and project.json because workers are instantiated dynamically (str2func) and
# invisible to mcc's static dependency analysis. Extra -a entries come from the path diff after
# qb.addpath_deps() + sepia_addpath(<method>) for the SEPIA methods in use, so the deployed path matches the
# desktop path. NB: mcc emits build/quidbbids AND build/run_quidbbids.sh (generated, not in the repo)
RUN cd /opt/quidbbids/containers \
    && matlab -batch "addpath('/opt/quidbbids', '/opt/quidbbids/containers') \
    p0 = split(path, pathsep); \
    qb.addpath_deps() \
    new = string([]); \
    for m = {'medi','segue','mrisc','mritools'}
        sepia_addpath(char(m)) \
        new = [new, setdiff(split(path, pathsep), [p0, new])]; \
    end \
    new = new(startsWith(new, '$DEPS'));    % Only our dependencies, not e.g. MATLAB add-on toolboxes \
    a = {'-m','quidbbids_mcr','-o','quidbbids','-d','/opt/quidbbids/containers/build','-v', \
         '-a','/opt/quidbbids/+qb','-a','$DEPS','-a','/opt/quidbbids/project.json'}; \
    for p = unique(new)
        a(end+1:end+2) = {'-a', char(p)}; \
    end \
    mcc(a{:})"

# ---- 5. MRtrix3 (DWIprepWorker calls fod2fixel/fixel2voxel/fixel2peaks via system()) ----
RUN apt-get install -y --no-install-recommends mrtrix3 && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- 6. SynthStrip: mri_synthstrip from the stage above (alternative to HD-BET, see docs/installation.rst) ----
COPY --from=synthstrip /freesurfer /freesurfer
COPY --from=synthstrip /usr/local /usr/local

# ---- 7. HD-BET (brain extraction via pip; alternative to mri_synthstrip, see docs/installation.rst) ----
RUN pip install --break-system-packages --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu \
    && pip install --break-system-packages --no-cache-dir hd-bet

RUN useradd -m -u 1000 quidb && chown -R quidb:quidb /opt/quidbbids /home/quidb
USER quidb
WORKDIR /data

# mcc wrapper: run_quidbbids.sh <runtime-root> [args...]; the MATLAB installation in this image acts as the runtime
# root, so the compiled app runs without a license. Override with --entrypoint matlab for licensed MATLAB use.
ENTRYPOINT MATLAB_ROOT="$(dirname "$(dirname "$(readlink -f "$(command -v matlab)")")")"; \
    exec /opt/quidbbids/containers/build/run_quidbbids.sh "$MATLAB_ROOT" "$@"
CMD ["--help"]
