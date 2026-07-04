OPTIMIZE LOOP ARBEITSWEISE

Diese Datei ist nur eine Arbeitsanweisung fuer Codex.
Sie ist keine Runtime-Config.
Sie ist kein Setup-SOT.
Sie ist keine Quelle fuer config.sh.
Sie dient nur dazu, die gemeinsame Arbeitsweise bei der Variablen-Liste nicht wieder falsch zu machen.

Die Datei fedora43-ai.md ist die Arbeitsliste.
Sie enthaelt immer alle aktuell bekannten Variablen.
Sie enthaelt jede Variable genau einmal.
Doppelte Variablen werden in der Liste ausgelassen.
Die Nummerierung bleibt global und fortlaufend.

Jedes Repo beginnt mit exakt einer GitHub-URL-Zeile.
Darunter werden die Dateiabschnitte mit diesen Blockzeilen getrennt:
#env_example
#config.conf_example
#container_example

Unter den Blockzeilen stehen die Variablen aus der jeweiligen Example-Datei.
Wenn eine Example-Datei fuer ein Repo keine Variablen enthaelt, bleibt der Block leer.
Zwischen GitHub-URL, Blockzeilen und Variablen stehen keine Kommentare.

Das Format jeder Variablenzeile ist exakt:
NUMMER. VARNAME<TAB>ERKLAERUNG

Nach der Nummer steht nur der Varname.
Keine Repo-Spalte.
Keine Datei-Spalte.
Keine Typ-Spalte.
Keine automatisch erfundenen Kategorien.

Rechts vom Tab steht nur das, was der User in der aktuellen gemeinsamen Durchsprache ausdruecklich entschieden hat.
Wenn der User zu einer Variable noch nichts entschieden hat, bleibt rechts vom Tab leer.
Nicht raten.
Nicht aus Code-Kommentaren ableiten.
Nicht aus alten Examples ableiten.
Nicht aus Nachbarprojekten ableiten.
Nicht vorausfuellen.

Die Loop-Arbeit laeuft so:
1. Alle Variablennamen bleiben in fedora43-ai.md sichtbar.
2. Der User geht die Variablen der Reihe nach durch.
3. Codex traegt nur die besprochene Entscheidung rechts vom Tab ein.
4. Codex laesst alle spaeteren unbesprochenen Variablen unangetastet und leer.
5. Codex gibt danach wieder die komplette Liste aus, ohne unbesprochene Kommentare zu erfinden.

Wenn eine Variable als required entschieden wurde, rechts schreiben:
required

Wenn eine Variable optional entschieden wurde, rechts schreiben:
optional

Wenn ein Default-Preset entschieden wurde, rechts schreiben:
required; default preset WERT
oder
optional; default preset WERT

Wenn eine Autofill-Regel entschieden wurde, rechts schreiben:
required; autofill blank if ANDERE_VAR=wert

Wenn mehrere Entscheidungen gelten, mit Semikolon trennen.
Keine neue Syntax erfinden.
Keine Kommentare vor oder nach der Liste einfuegen.

Bei DB-Variablen nur dann required/autofill eintragen, wenn der User es fuer dieses Projekt oder diese Variablengruppe ausdruecklich gesagt hat.
Nicht automatisch alle DB-Variablen kategorisieren.

Bei neuen Repos oder neuen Variablen:
Alle neuen Variablennamen anhaengen.
Rechts vom Tab leer lassen, bis der User sie bespricht.

Bei Korrekturen:
Nur die betroffenen Zeilen aendern.
Keine bereits noch nicht besprochenen Zeilen kommentieren.
Keine fertigen Entscheidungen ohne User-Anweisung umdeuten.

Ziel:
Codex bleibt im Loop diszipliniert.
Der User entscheidet.
Codex schreibt mit.
