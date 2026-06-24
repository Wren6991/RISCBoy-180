rb180_datasheet.pdf: $(wildcard *.adoc) diagram/ pdf-theme.yml
	asciidoctor-pdf -a compress rb180_datasheet.adoc

.PHONY: view
view: rb180_datasheet.pdf
	open rb180_datasheet.pdf

.PHONY: clean
clean:
	rm -f rb180_datasheet.pdf
