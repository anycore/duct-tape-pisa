CC = gcc
SCANNER = flex
PARSER = bison

TOP = .

OPTIMIZATION = -O3 
FLAGS = -g -D__STDC_FORMAT_MACROS
LIBS = -lfl

WARN = 


CFLAGS = $(OPTIMIZATION) $(FLAGS) $(WARN)


DT_OBJ = $(TOP)/obj/lex.yy.o \
	$(TOP)/obj/support.o \
	$(TOP)/obj/dt.tab.o

# All sources ###############################################################

$(TOP)/bin/dt: $(DT_OBJ)
	$(CC) -o $(TOP)/bin/dt $(CFLAGS) $(DT_OBJ) $(LIBS)

# CC compile ################################################################

$(TOP)/src/lex.yy.c : $(TOP)/src/dt.l $(TOP)/src/dt.tab.h
	$(SCANNER) -o$(TOP)/src/lex.yy.c $(TOP)/src/dt.l

$(TOP)/obj/lex.yy.o : $(TOP)/src/lex.yy.c
	$(CC) $(CFLAGS) -c $(TOP)/src/lex.yy.c -o $(TOP)/obj/lex.yy.o 

$(TOP)/src/dt.tab.c : $(TOP)/src/dt.y 
	$(PARSER) -v -d $(TOP)/src/dt.y -o$(TOP)/src/dt.tab.c

$(TOP)/src/dt.tab.h : $(TOP)/src/dt.y 
	$(PARSER) -v -d $(TOP)/src/dt.y -o$(TOP)/src/dt.tab.c

$(TOP)/obj/dt.tab.o : $(TOP)/src/dt.tab.c $(TOP)/src/dt.tab.h
	$(CC) $(CFLAGS) -c $(TOP)/src/dt.tab.c -o $(TOP)/obj/dt.tab.o 

$(TOP)/obj/support.o : $(TOP)/src/support.c $(TOP)/src/support.h $(TOP)/src/dt.tab.h
	$(CC) $(CFLAGS) -c $(TOP)/src/support.c -o $(TOP)/obj/support.o 

# Cleanup ###################################################################

 
clean:
	rm -f $(TOP)/bin/* $(DT_OBJ) $(TOP)/src/lex.yy.c $(TOP)/src/dt.tab.* $(TOP)/src/dt.output
