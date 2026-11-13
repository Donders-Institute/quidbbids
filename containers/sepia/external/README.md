# SEPIA external toolboxes (not in git)

Place SEPIA's non-git dependencies here before building the container image
(`containers/apptainer.def` / `containers/Dockerfile`), each in a folder named after its
`SpecifyToolboxesDirectory.m` variable without the `_HOME` suffix, e.g.:

    containers/sepia/external/SEGUE/
    containers/sepia/external/MRISC/
    containers/sepia/external/STISuite/

Everything in this folder except this README is git-ignored. See `docs/containers.rst` for details.
