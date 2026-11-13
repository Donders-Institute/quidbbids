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
#       docker run --rm -v /data/bids:/data/bids quidbbids:v1.0.0 /data/bids \
#           --deliverables MWFmap,Chimap --configfile /data/bids/code/quidbbids_config.json
#
# Build (compiling with mcc needs a MATLAB license at build time):
# NB: Packages in containers/sepia/external are included as SEPIA dependencies (e.g.: 'SEGUE', 'MRISC' and 'STISuite',
#     i.e. named as the SpecifyToolboxesDirectory.m variables without the '_HOME' suffix)
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

# ---- Main image: full MATLAB + compiled app + external tools ----
FROM mathworks/matlab:${MCR_TAG}
ARG MLM_LICENSE_FILE
ENV FREESURFER_HOME=/freesurfer PATH=/freesurfer:${PATH}
ENV PYTHONUSERBASE=/freesurfer/env
ENV SEPIA_TOOLBOXES=/opt/quidbbids/dependencies/sepia/external
ENV DEPS=/opt/quidbbids/dependencies

# ---- 1. Clone QuIDBBIDS (the MATLAB dependencies come along as git submodules) ----
RUN apt-get update && apt-get install -y --no-install-recommends git fonts-noto-color-emoji fonts-noto-core \
    && git clone --recurse-submodules --depth 1 https://github.com/Donders-Institute/quidbbids.git /opt/quidbbids

# SEPIA's external toolboxes from the build context (repo root); moved into place in section 2
COPY containers/sepia/external/ /opt/sepia-external/

# ---- 2. SEPIA: point SpecifyToolboxesDirectory.m to the copied and submodule toolboxes ----
RUN mv /opt/sepia-external $DEPS/sepia/external \
    && cp $DEPS/sepia/SpecifyToolboxesDirectory.template.m $DEPS/sepia/SpecifyToolboxesDirectory.m \
    && sed -i -E -e "s|^([A-Za-z]+)_HOME *= .*|\1_HOME = '$DEPS/sepia/external/\1/';|" \
                 -e "s|^FANSI_HOME *= .*|FANSI_HOME = '$DEPS/FANSI_toolbox/';|" \
                 -e "s|^MEDI_HOME *= .*|MEDI_HOME = '$DEPS/MEDI_toolbox/';|" \
                 -e "s|^MRITOOLS_HOME *= .*|MRITOOLS_HOME = '$DEPS/sepia/external/MRITOOLS/';|" \
                 $DEPS/sepia/SpecifyToolboxesDirectory.m

# ---- 3. CompileMRI's prebuilt mritools bundle (ROMEO, CLEAR-SWI, ...); MRITOOLS_HOME points here ----
ARG COMPILEMRI_VERSION=4.9.1
RUN wget -q "https://github.com/korbinian90/CompileMRI.jl/releases/download/v${COMPILEMRI_VERSION}/"\
"mritools_linux_x64_${COMPILEMRI_VERSION}.tar.gz" -O /tmp/mritools.tar.gz \
    && mkdir -p $DEPS/sepia/external/MRITOOLS \
    && tar -xzf /tmp/mritools.tar.gz -C $DEPS/sepia/external/MRITOOLS --strip-components=1 \
    && rm /tmp/mritools.tar.gz

# Set external toolboxes that are not installed to empty, so SEPIA skips them without warnings
RUN for var in $(sed -n "s/^\([A-Za-z]*_HOME\) *=.*/\1/p" $DEPS/sepia/SpecifyToolboxesDirectory.m); do \
        path=$(sed -n "s/^$var *= *'\([^']*\)'.*/\1/p" $DEPS/sepia/SpecifyToolboxesDirectory.m); \
        if [ -n "$path" ] && [ ! -d "$path" ]; then \
            sed -i "s|^$var *= .*|$var = [];|" $DEPS/sepia/SpecifyToolboxesDirectory.m; \
        fi; \
    done

# ---- 4. Compile the standalone app with mcc ----
RUN wget -q https://www.mathworks.com/mpm/glnxa64/mpm -O /tmp/mpm && chmod +x /tmp/mpm \
    && MATLAB_ROOT="$(dirname "$(dirname "$(readlink -f "$(command -v matlab)")")")" \
    && /tmp/mpm install --matlabroot "$MATLAB_ROOT" --release "$(basename "$MATLAB_ROOT")" \
        --products MATLAB_Compiler \
    && rm /tmp/mpm
# -a bundles +qb, project.json and each top-level dependency dir (bundling every subdir makes the
# deployed app crash at startup). Workers are instantiated dynamically (str2func) and invisible to
# mcc's static analysis. NB: mcc emits build/quidbbids AND build/run_quidbbids.sh (generated, not in repo)
# remove non-code .m files that mcc cannot parse (text readme/changelog/script files)
RUN rm -f "$DEPS/EPG-X/Additional_bSSFPX_CEST.m" "$DEPS/MEDI_toolbox/README.m" "$DEPS/MEDI_toolbox/UPDATES.m" \
    && rm -f "$DEPS/FANSI_toolbox"/script_*.m               # Demo scripts with syntax mcc cannot parse \
    && rm -rf "$DEPS/spm/external" "$DEPS/spm/toolbox"      # Huge, not needed
    && find "$DEPS/sepia/external" -name sfb3D_A.m -delete  # STI Suite HTML 404 page misnamed .m, breaks mcc \
RUN cd /opt/quidbbids/containers \
    && matlab -batch "addpath('/opt/quidbbids', '/opt/quidbbids/containers'), \
    a = {'-m','quidbbids_mcr','-o','quidbbids','-d','/opt/quidbbids/containers/build','-v', \
         '-a','/opt/quidbbids/+qb','-a','/opt/quidbbids/project.json'}; \
    for d = fullfile('$DEPS', setdiff({dir('$DEPS').name}, {'.', '..'})), \
        a(end+1:end+2) = {'-a', char(d)}; \
    end, \
    mcc(a{:})" \
    && test -f /opt/quidbbids/containers/build/run_quidbbids.sh    # Fail the build if mcc did not complete

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
