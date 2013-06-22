#############################################################################
# final pdf name
#
NAME = dt

#############################################################################
# list of all included chapters
#
CHAPTERS = abstract.tex \
				   intro.tex \
				   language.tex \
				   conc.tex \
				   usage.tex 

#############################################################################
# list of graphs that need to be built and included (all should be named .pdf,
# but none of the source files should be .pdf files!)
#
GRAPHS = 

#############################################################################
# list of diagrams that need to be built and included (all should be named .pdf,
# but none of the source files should be .pdf files!)
#
DIAGRAMS = 

#############################################################################
# final pdf build command
#
$(NAME).pdf : $(NAME).tex $(NAME).bib $(GRAPHS) $(DIAGRAMS) $(CHAPTERS)
	pdflatex $(NAME)
	bibtex $(NAME)
	pdflatex $(NAME)
	pdflatex $(NAME)

#############################################################################
# build rules
#

%.pdf: %.eps
	epstopdf $<

%.eps: %.dia
	dia -e $@ $< 

%.eps: %.gnuplot
	gnuplot $< > $@

clean: 
	rm -f *.toc *.blg *.aux *.dvi *.pdf *.lo* *.bbl $(GRAPHS) $(DIAGRAMS)

#############################################################################
# old stuff
#

