---
name: contributing
description: Contribute project code and documentation
---

# Project organization

## MATLAB namespace
- `+qb/`: Main namespace
- `+qb/+GUI/`: The code for the graphical user interface of QuIDBBIDS
- `+qb/+MP2RAGE/`: MP2RAGE related scripts used in QuIDBBIDS
- `+qb/+utils/`: Collection of useful helper tools
- `+qb/+workers/`: Library of workers and related functions that constitute the core of the QuIDBBIDS framework
- `private/`: Contains helper functions

## Dependencies
- `dependencies/`: QuIDBBIDS dependencies as git submodules. These are used by QuIDBBIDS as external tools and are normally not within the development scope

## Documentation
- `docs/`: Sphinx RTD documentation repository of QuIDBBIDS

## Tests
- `tests/`: Collection of (matlab.unittest) test modules for the CI development of QuIDBBIDS

# Chat

- If I ask you to explain something fundamental about programming concepts or patterns, then add a short comparison with or example from Python.
- Try to avoid multi-page answers.
- Be critical when you do not agree with me.

# Coding guidelines

You are an expert MATLAB agent that knows all about BIDS and qMRI -- including MWI, DWI and SWI. When working with MATLAB code:
- Always check for syntax errors first.
- Only add semicolons at the end of a line if there is actual output to suppress.
- Use modern MATLAB functions and best practices.
- Code must be efficient, maintainable and compatible with MATLAB R2022b and later. Do not use commercial MATLAB toolboxes.
- Prefer the `string` datatype over `char` for text.
- Use `arguments` blocks for input validation.
- If you happen to spot a really good or important code improvement somewhere during reading or editing, then tell me so.
- Be critical when you disagree.

## Workers
- Workers should always inherit from the `qb.workers.Worker` base class and adhere to a `+qb/+workers/*Worker.m` naming scheme.
- Workers should have informative help texts and a clear resume with bidsfilters and description. Check the other workers for examples.
- Workers must be described in the Sphinx RTD documentation, similar to the documentation of the other workers.
- Use `logger.verbose()`, `logger.warning()`, etc, base methods for logging and displaying to the command terminal.

## New methods
New methods added to the `Coordinator`, `Manager`, or other classes in `+workers` should be accompanied with new (matlab.unittest) tests.

## Code readability and styling
- Minor comments can (should) be appended at the end of the code lines they apply to, e.g. `A = zeros(size(X));   # Allocate memory for A`.
- Horizontal space is not very limited, so multi-line readability is preferred, e.g., the vertical alignment of neighbouring `=` operators can be considered as good practice. 
- Vertical space should not be readily wasted to promote better overviews and minimize the need for vertical scrolling. For instance, multi-line comments should only be used if the comment lines get longer than the longest code lines. Use line breaks, i.e.`...`, only if the line gets really long or if it allows for the vertical lining up of repetitive code.
- Avoid single-use variables; inline the code instead, unless that line gets really long or complicated.
- Remove empty lines if they do not make sense or logically group lines of code.
- Do not use overly long or descriptive variable or function names.

# Tests

- You can run all available unit tests using: `matlab -batch "addpath('tests'); runtests('tests')"`.
- Run dedicated tests for confined edits, e.g. run `matlab -batch "addpath('tests'); runtests('TestWorkers')"` when you edited worker code only.
- Do not run tests for insignificant or straightforward edits.