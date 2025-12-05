=========================
Contributing to QuIDBBIDS
=========================

Project organization
--------------------

* `+qb/ <./+qb>`__ - The main namespace with the core packages and functions:

  - ``+MP2RAGE/`` - The `MP2RAGE related scripts <https://github.com/Donders-Institute/MP2RAGE-related-scripts>`__ used in QuIDBBIDS
  - ``+utils/`` - A collection of useful helper tools
  - ``+workers/`` - A library of workers and related functions that constitute the core od the QuIDBBIDS framework
  - ``private/`` - Helper functions that are meant for internal use only

* `dependencies/ <./dependencies>`_ - The Sphinx `RTD <https://quidbbids.readthedocs.io>`__ documentation repository
* `docs/ <./docs>`_ - The Sphinx `RTD <https://quidbbids.readthedocs.io>`__ documentation repository
* `resources/ <./resources>`_ - The MATLAB `package definition <https://nl.mathworks.com/help/matlab/ref/mpackage.json.html?s_tid=srchtitle_support_results_1_mpackage.json>`__ for QuIDBBIDS
* `tests/ <./tests>`_ - The collection of (matlab.unittest) test modules for the `CI development <https://github.com/features/actions>`__ of QuIDBBIDS

How to contribute code
----------------------

The preferred way to contribute to the QuIDBBIDS code base or documentation is to use a `forking workflow <https://www.atlassian.com/git/tutorials/comparing-workflows/forking-workflow>`__, 
i.e. fork the ``dev`` branch of the `main repository <https://github.com/Donders-Institute/quidbbids>`__, create a feature branch, and submit a pull request for the ``dev`` branch. 
If you are unsure what that means, here is a set-up workflow you may wish to follow:

0. Fork the `project repository <https://github.com/Donders-Institute/quidbbids>`_ on GitHub, by clicking on the “Fork” button near the top of the page — this will create a personal copy of the repository.

1. Set up a clone of the repository on your local machine and connect it to both the “official” and your copy of the repository on GitHub:

   .. code-block:: console

      $ git clone --recurse-submodules -b dev https://github.com/Donders-Institute/quidbbids.git
      $ cd quidbbids
      $ git remote rename origin official
      $ git remote add origin git://github.com/[YOUR_GITHUB_USERNAME]/quidbbids

2. In case you want to contribute to the RTD documentation, set up a Python virtual environment and install the built dependencies:

   .. code-block:: console

      $ python -m venv docs/venv        # Or use any other tool (such as conda)
      $ source docs/venv/bin/activate   # On Linux, see the documentation for other operating systems
      $ pip install -r docs/requirements.txt

3. When you wish to start working on your contribution, create a new branch:

   .. code-block:: console

      $ git checkout -b [topic_of_your_contribution]

4. When you are done with coding, you should then test, commit and push your work to GitHub:

   .. code-block:: console

      >> runtests('tests')                                   # Run this from the quidbbids directory or use MATLAB's `Test Browser App <https://nl.mathworks.com/help/matlab/ref/testbrowser-app.html>`__.
      $ docs/make html                                       # For the docs, run this to generate the files on your local machine (on Windows use ``docs/make.bat html``) and open ``docs/_build/html/index.html``
      $ git commit -am "A SHORT DESCRIPTION OF THE CHANGES"  # Run this every time you have made a set of changes that belong together
      $ git push -u origin topic_of_your_contribution        # Run this when you are done and the tox tests are passing

Git will provide you with a link which you can click to initiate a pull request (if any of the above seems overwhelming, you can look up the `Git <http://git-scm.com/documentation>`__ 
or `GitHub <https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request>`__ documentation on the web)

Coding guidelines
-----------------

Please check that your contribution complies with the following rules before submitting a pull request:

* Workers (i.e. ``+qb/+workers/*Worker.m`` files that inherit from the ``Worker`` class) should have informative help texts and a clear resume with bidsfilters and description. Also, the worker must be described in the Sphinx RTD documentation
* New methods added to the Coordinator, should be accompanied with new (matlab.unittest) tests
* To improve code readability, minor comments can (should) be appended at the end of the code lines they apply to (even if that means right scrolling)
* Horizontal space is not limited, so multi-line readability is preferred, e.g. the vertical alignment of ``=`` operators (i.e. padded horizontally with whitespaces)
* Vertical space should not be readily wasted to promote better overviews and minimize the need for vertical scrolling
