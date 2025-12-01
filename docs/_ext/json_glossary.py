import json
from pathlib import Path
from docutils import nodes
from docutils.parsers.rst import Directive


class JSONGlossaryDirective(Directive):
    """
    Usage:

        .. jsonglossary:: path/to/file.json
    """
    required_arguments = 1

    def run(self):
        env = self.state.document.settings.env

        json_path = Path(self.arguments[0])
        if not json_path.is_absolute():
            json_path = Path(env.srcdir) / json_path

        # Load JSON glossary
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        gloss = nodes.definition_list()

        # JSON is assumed like:
        # { "R1map": "Definition...", "S0map": "Definition..." }
        for term, definition in data.items():
            term_node = nodes.term(text=term)
            def_node = nodes.definition()
            def_node += nodes.paragraph(text=definition)

            gloss += nodes.definition_list_item("", term_node, def_node)

        return [gloss]


def setup(app):
    app.add_directive("jsonglossary", JSONGlossaryDirective)
    return {"version": "1.0"}
