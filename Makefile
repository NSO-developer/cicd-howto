PANDOC_OPTIONS=--toc
DOC_DIR=.
DOCS_UNFILTERED:=$(wildcard ./*.md)
DOCS=$(filter-out ./README.md, $(DOCS_UNFILTERED))
DOCS_HTML=$(DOCS:.md=.html)
DOCS_PDF=$(DOCS:.md=.pdf)
DOCS_WORD=$(DOCS:.md=.docx)

all: docs 

docs: html

html: $(DOCS_HTML)
word: $(DOCS_WORD)
pdf:  $(DOCS_PDF)

%.docx: %.md 
	pandoc $(PANDOC_OPTIONS) -o $@ $<
%.html: %.md 
	pandoc $(PANDOC_OPTIONS) -c $(DOC_DIR)/pandoc.css -N -o $@ $<
%.pdf: %.md 
	pandoc $(PANDOC_OPTIONS) -o $@ $<

clean:
	rm -f $(DOCS_HTML) $(DOCS_PDF) $(DOCS_WORD)
