function helptext = help(items)
%HELP returns or prints HELPTEXT for the ITEMS
%
% Examples
%   qb.workers.help('QSMWorker')
%   qb.workers.help(["R1map", "localfmask"])

items        = string(items);
descriptions = strings(size(items));
glossfile    = fullfile(fileparts(mfilename('fullpath')), 'glossary.json');
if isfile(glossfile)
    glossary = jsondecode(fileread(glossfile));
end
for n = 1:numel(items)
    item = items(n);
    if isfield(glossary, item)
        descriptions(n) = glossary.(item);
    elseif endsWith(item, "_ortho")
        descriptions(n) = sprintf("A 2D montage with 3 orthogonal (QC) slices of '%s'", erase(item, "_ortho"));
    elseif contains(item, "Worker") && exist("qb.workers." + item, 'class')
        descriptions(n) = join([qb.workers.(item).description; "";
                                "needs:   " + join(qb.workers.(item).needs, ', ')
                                "usesGPU: " + qb.workers.(item).usesGPU], newline);
    end
end

if nargout
    helptext = descriptions;
else
    padding = max(strlength(items));
    for n = 1:numel(items)
        fprintf('%-*s : %s\n', padding, items(n), descriptions(n))
    end
end
