# Changelog

*All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)*

Release notes (with codenames) are also published on the [GitHub releases page](https://github.com/Donders-Institute/quidbbids/releases).

## [dev]

Current development version: `0.9.0-dev` (see `project.json`) — unreleased changes on the `dev` branch since v0.4.0.

### Added
- Workflow Control Panel main GUI (`quidb.start_GUI()`): setup buttons (Inclusion, Catalog, Config, Outputdir, Workdir, Reset), workflow mask/graph visualization, Load/Save/Start buttons, and an info table summarizing the dataset and settings
- BIDS include/exclude filters as `Coordinator` properties with a dedicated inclusion editor GUI; the filtered layout is pruned and the workflow mask redrawn on change
- New `R2starWorker` split off from `QSMWorker` (GitHub issue #59), using the SEPIA workdir
- Multiple brain-extraction methods/options (incl. BET fallback) for `MEGREprepWorker`/`VFAprepWorker`
- `NumberShots` heuristics for `MP2RAGEWorker` (GitHub issue #55)
- Variable-TR protocol support in `MCR_GPUWorker` (via the vTR-qMRI submodule)
- Joint Pade R1-R2*-M0 fit in `SCRWorker` (replacing DESPOT1/mean-R2*)
- `Worker.collect()` and Manager updates to speed up HPC workflows
- Workflow-graph interactions: click a worker node to force recomputation, click a workitem node to toggle it as a deliverable
- `qb.tutorialdata` download tool and a revised QuIDBBIDS 101 tutorial
- Unit tests for the include/exclude filters

### Changed
- Major refactoring: inclusion/exclusion filtering is now a Coordinator function (no longer edited in the ConfigEditor); the BIDS layout is loaded in the Coordinator superclass
- Worker `description`/`needs`/`usesGPU` are `Constant` properties; `products` renamed to `deliverables` and `workitems()` to `catalog()`
- ConfigEditor, deliverables catalog, and worker-selection GUIs refactored to `uigridlayout`; worker help text added to the ConfigEditor
- Stop indexing `IntendedFor` dependencies to speed up `bids.layout()`

### Fixed
- Loading saved workflow settings in a changed environment (moved dataset, different OS paths)
- Safeguards around workers that mess with the MATLAB path (SEPIA), irregular SEPIA output file naming, and SEPIA GUI `r2s` subtree editing
- `MEGREprepWorker`/`VFAprepWorker` handle absent phase data; `part=''` implicitly denotes `part='mag'`
- Workflow drawing fixes in the GUI (Load button, graph redraw, team assembly for workers that make a single workitem)
- Various unit-test and CI fixes

## [v0.4.0] - 2026-07-26 — "Don't Panic -- Mostly Harmless Diffusion"

### Added
- DI-MWI based on qsiprep NODDI/fixel data (`DWIprepWorker`, PR #38)
- New worker documentation

### Fixed
- Skip single-FA acquisitions and reset flip angles per acquisition (PR #36)
- `dictmatching` call now uses single precision and real data (PR #30)

## [v0.3.0] - 2026-04-15 — "One man's noise is another man's signal!"

### Added
- (t)MP-PCA denoising
- Use the `acq` label to group acquisitions

### Fixed
- Various worker bugfixes and documentation updates

## [v0.2.3] - 2026-03-13 — "Staying up-to-date"

Maintenance release before v0.3.0.

### Changed
- Modern named-value input arguments
- Added a check for updates and more tests

## [v0.2.2] - 2026-03-11 — "No package deal"

### Changed
- Replaced the MATLAB package file (`mpackage.json`) with a generic project file (`project.json`) to avoid toolbox-cache issues

## [V0.2.1] - 2026-02-28 — "Don't mess with me..."

### Added
- Custom `tag` added to output data processed with specific settings, e.g. to compare protocols (GitHub issue #8)

### Fixed
- Safeguard around workers that mess up the MATLAB path (SEPIA)

## [v0.1.0] - 2026-02-25 — "The fledgling is taking off"

No main GUI yet, but otherwise fairly functional.

### Added
- `parfeval` option next to `qsubfeval` for local parallel processing
- Worker `description`/`needs` as constant properties
- Report generation from the output directory; end products copied to the output directory with sidecar files
- Single precision in the MCR and R1R2s workers

## [V0.0.4] - 2026-01-15 — "Early bird bugfix release"

### Fixed
- Showstopper bugfixes on top of v0.0.3 (JSON config parsing, tree-node tagging)

## [v0.0.3] - 2026-01-14 — "Early bird release"

### Added
- GUI for the selection of workers
- GUI for editing config settings
- GUI for editing the data input (BIDS inclusion)
- Worker for processing MP2RAGE data
- Refactored codebase

## [v0.0.2] - 2025-10-27

Tag-only release (no GitHub release page).

### Fixed
- Brainmask selection and output basename construction via `bfile_set`

## [0.0.1] - 2025-04-09

### Added
- Initial setup of QuIDBBIDS

[dev]: https://github.com/Donders-Institute/quidbbids/compare/v0.4.0...HEAD
[v0.4.0]: https://github.com/Donders-Institute/quidbbids/compare/v0.3.0...v0.4.0
[v0.3.0]: https://github.com/Donders-Institute/quidbbids/compare/v0.2.3...v0.3.0
[v0.2.3]: https://github.com/Donders-Institute/quidbbids/compare/v0.2.2...v0.2.3
[v0.2.2]: https://github.com/Donders-Institute/quidbbids/compare/V0.2.1...v0.2.2
[V0.2.1]: https://github.com/Donders-Institute/quidbbids/compare/v0.1.0...V0.2.1
[v0.1.0]: https://github.com/Donders-Institute/quidbbids/compare/V0.0.4...v0.1.0
[V0.0.4]: https://github.com/Donders-Institute/quidbbids/compare/v0.0.3...V0.0.4
[v0.0.3]: https://github.com/Donders-Institute/quidbbids/compare/v0.0.2...v0.0.3
[v0.0.2]: https://github.com/Donders-Institute/quidbbids/releases/tag/v0.0.2
