function quidbbids_mcr(varargin)
%QUIDBBIDS_MCR Entry point of the compiled QuIDBBIDS app (MATLAB Runtime; no license needed at run time).
% Thin wrapper around qb.QuIDBBIDS (see docs/CLI.rst and docs/GUI.rst): parses flags, then makes the same
% calls you would type in MATLAB. CLI mode takes the BIDS dir as the first (positional) argument and runs
% the workflow; GUI mode (Workflow Control Panel with folder picker) is inferred when run without arguments.

% Force mcc to bundle toolbox functions that are only reached dynamically (SEPIA dispatches the R2* methods
% via str2func on the method-name strings, so mcc's static analysis never sees these calls)
%#function lsqnonlin optimoptions lsqcurvefit

    % Parse the command line arguments
    opts = struct('bidsdir', "", 'outputdir', "", 'workdir', "", 'configfile', "", 'deliverables', "", ...
                  'subjects', "", 'prefer', "", 'force', "", 'set', {{}}, 'gui', false, 'help', false);
    i = 1;
    while i <= numel(varargin)
        opt = lower(string(varargin{i}));
        if opt == "-h"                                      % Alias for --help
            opts.help = true; i = i + 1;
            continue
        end
        if ~startsWith(opt, "--")                           % Positional argument: the BIDS dir
            if strlength(opts.bidsdir) > 0
                error('QuIDBBIDS:UnknownOption', 'Unexpected argument: %s (try --help)', opt);
            end
            opts.bidsdir = string(varargin{i}); i = i + 1;
            continue
        end
        key = char(erase(opt, "--"));
        if key == "help"                                    % Boolean flag
            opts.(key) = true; i = i + 1;
        elseif key == "set" && i < numel(varargin)          % Repeatable KEY=VALUE
            opts.set{end+1} = string(varargin{i+1}); i = i + 2;
        elseif isfield(opts, key) && i < numel(varargin)    % Value flags (names match the struct fields)
            opts.(key) = string(varargin{i+1}); i = i + 2;
        else
            error('QuIDBBIDS:UnknownOption', 'Unknown or incomplete option: %s (try --help)', opt);
        end
    end
    if nargin == 0
        opts.gui = true;                                    % No arguments -> GUI mode (like qb.QuIDBBIDS())
    end

    % Show help
    if opts.help || (strlength(opts.bidsdir) == 0 && ~opts.gui)
        ver = qb.version();                                 % From project.json (bundled into the compiled app)
        disp(strjoin([
            "  ___       ___ ___  ___ ___ ___ ___  ___"
            " / _ \ _  _|_ _|   \| _ ) _ )_ _|   \/ __|"
            "| (_) | || || || |) | _ \ _ \| || |) \__ \"
            " \__\_\\_,_|___|___/|___/___/___|___/|___/"
            ""
            "Quantitative Imaging Derived Biomarkers in BIDS"
            "‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"
            "This is the entry point for running containerized QuIDBBIDS (v" + ver + ") without a MATLAB"
            "license. It is a thin wrapper around the mcc-compiled qb.QuIDBBIDS app and can be called"
            "from the Apptainer or Docker command line. It parses the command line arguments and calls"
            "the same methods you would call in desktop MATLAB."
            ""
            "Usage:"
            "  apptainer run quidbbids-<version>.sif                    # GUI mode (+ data binding)"
            "  apptainer run quidbbids-<version>.sif BIDSDIR [options]  # CLI mode (+ data binding)"
            "  docker run quidbbids:<version>                           # GUI mode (+ data binding + X display)"
            "  docker run quidbbids:<version> BIDSDIR [options]         # CLI mode (+ data binding)"
            ""
            "Options (for CLI mode):"
            "  --outputdir PATH     output dir  (default: BIDSDIR/derivatives/QuIDBBIDS)"
            "  --workdir PATH       work dir    (default: BIDSDIR/derivatives/QuIDBBIDS_work)"
            "  --configfile PATH    config file (e.g. BIDSDIR/code/quidbbids_config.json)"
            "  --deliverables LIST  comma-separated deliverables (e.g. MWFmap,Chimap)"
            "  --subjects LIST      comma-separated subjects to process (default: all)"
            "  --prefer LIST        workers to prefer for resumes"
            "  --force LIST         workers to force re-run"
            "  --set KEY=VALUE      set config.<KEY>.value (repeatable), e.g."
            "                       --set MEGREprepWorker.brainmask.method=hd-bet"
            "  -h, --help           show this help"
            ""
            "Apptainer examples:"
            "  apptainer run --bind /data/bids:/data/bids quidbbids-v" + ver + ".sif"
            "  apptainer run --bind /data/bids:/data/bids quidbbids-v" + ver + ".sif /data/bids \\"
            "      --deliverables MWFmap --configfile /data/bids/code/quidbbids_config.json"
            "  apptainer run --bind /data/bids:/data/bids quidbbids-v" + ver + ".sif /data/bids \\"
            "      --subjects sub-01,sub-02 --set MEGREprepWorker.brainmask.method=hd-bet"
            ""
            "Docker examples:"
            "  docker run --rm -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \\"
            "      -v /data/bids:/data/bids quidbbids:v" + ver
            "  docker run --rm -v /data/bids:/data/bids quidbbids:v" + ver + " /data/bids \\"
            "      --deliverables MWFmap,Chimap --configfile /data/bids/code/quidbbids_config.json"
            "  docker run --rm -v /data/bids:/data/bids quidbbids:v" + ver + " /data/bids \\"
            "      --subjects sub-01,sub-02 --set MEGREprepWorker.brainmask.method=hd-bet"
            ""
            "See also: https://quidbbids.readthedocs.io/en/latest/containers.html"], newline))
        return
    end

    % Create a QuIDBBIDS object and set its properties
    if opts.gui
        quidb = qb.QuIDBBIDS();                             % GUI mode per docs/GUI.rst (no arguments given)
    else
        quidb = qb.QuIDBBIDS(opts.bidsdir, opts.outputdir, opts.workdir, opts.configfile);
        quidb.interactive = false;                          % Scripted CLI run: no popups (docs/CLI.rst)
    end
    if strlength(opts.deliverables) > 0
        quidb.deliverables = split_list(opts.deliverables);
    end
    for k = 1:numel(opts.set)                               % --set maps to config.<KEY>.value
        eq = strfind(opts.set{k}, '=');
        key = regexp(char(extractBefore(opts.set{k}, eq(1))), '[^.]+', 'match');
        quidb.config = set_config_value(quidb.config, key, convert_value(extractAfter(opts.set{k}, eq(1))));
    end
    for w = split_list(opts.prefer)                         % --prefer maps to resumes.<worker>.preferred
        if isfield(quidb.resumes, char(w)), quidb.resumes.(char(w)).preferred = true; end
    end

    %--- GUI MODE: Open the workflow panel and wait until all GUIs are closed
    if opts.gui
        quidb.start_GUI();
        while any(arrayfun(@isvalid, findall(groot, 'Type', 'uifigure')))
            pause(1)
        end
        return
    end

    %--- CLI MODE: Run the workflow
    mgr = quidb.get_manager();
    if strlength(opts.force) > 0
        mgr.force = split_list(opts.force);
    end
    if strlength(opts.subjects) > 0
        mgr.start_workflow(split_list(opts.subjects));
    else
        mgr.start_workflow();
    end
end

%% Helper functions for parsing CLI arguments

function list = split_list(s)
    list = string(strtrim(split(s, ",")));
    list(list == "") = [];
end

function val = convert_value(s)
    val = str2double(s);
    if isnan(val)
        switch lower(s)
            case "true",  val = true;
            case "false", val = false;
            otherwise, parts = split_list(s); if numel(parts) > 1, val = parts; else, val = s; end
        end
    end
end

function s = set_config_value(s, parts, val)
    f = char(parts{1});
    if isscalar(parts)
        if ~(isfield(s, f) && isstruct(s.(f)) && isfield(s.(f), 'value'))
            error('QuIDBBIDS:BadConfigKey', 'Unknown config key: %s', f);
        end
        s.(f).value = val;
    else
        s.(f) = set_config_value(s.(f), parts(2:end), val);
    end
end
