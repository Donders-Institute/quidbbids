# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Path setup --------------------------------------------------------------

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.

import json
from pathlib import Path
from datetime import date


# -- Project information -----------------------------------------------------

project    = 'QuIDBBIDS'
copyright  = f"2025-{date.today().year}, Jose Marques"
author     = 'Marcel Zwiers'
master_doc = 'index'

# The full version, including alpha/beta/rc tags from file
with open(Path(__file__).parents[1]/'resources'/'mpackage.json') as fid:
  release = json.load(fid)['version']

# -- General configuration ---------------------------------------------------

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom
# ones.
nitpicky      = True
extensions    = ['myst_parser', 'sphinx_design']
source_suffix = {'.rst': 'restructuredtext',
                 '.md': 'markdown'}

# Add any paths that contain templates here, relative to this directory.
templates_path = ['_templates']

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This pattern also affects html_static_path and html_extra_path.
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']


# -- Options for HTML output -------------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.

html_theme         = 'sphinx_rtd_theme'
highlight_language = "none"

# Replace the "View page source" link with "Edit on GitHub"
html_context = {
  'display_github': True,
  'github_repo': 'quidbbids',
  'github_user': 'Donders-Institute',
  'github_version': 'main',
  'conf_py_path': '/doc/',          # Needs leading and trailing slashes
}

# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".

html_static_path = ['_static']
# html_favicon     = "./_static/quidbbids_logo.png"
html_logo        = "./_static/quidbbids_logo.png"
html_theme_options = {
    'logo_only':        True,   # Only show logo (no project name)
    'version_selector': False,  # Optional: Hide version
}
