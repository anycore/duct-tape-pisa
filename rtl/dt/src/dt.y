/* 
 * dt.y parser 
 */

%glr-parser

%{
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include "support.h"


/* set to 1 to trace the parser when you run dt on a program */
#define YYDEBUG 0
%}

%union {
    char *string;
    int64_t ivalue;
    float fvalue;
    void *mentry;
}

%token OP_J OP_JAL OP_JR OP_JALR OP_BEQ OP_BNE
%token OP_BLEZ OP_BGTZ OP_BLTZ OP_BGEZ
%token OP_BCF OP_BCT

%token OP_LB OP_LBU OP_LH OP_LHU OP_LW OP_DLW
%token OP_L_S OP_L_D OP_LWL OP_LWR
%token OP_SB OP_SH OP_SW OP_DSW OP_DSZ
%token OP_S_S OP_S_D OP_SWL OP_SWR

%token OP_ADD OP_ADDI OP_ADDU OP_ADDIU
%token OP_SUB OP_SUBU OP_MULT OP_MULTU
%token OP_DIV OP_DIVU OP_MFHI OP_MTHI
%token OP_MFLO OP_MTLO OP_AND OP_ANDI
%token OP_OR OP_ORI OP_XOR OP_XORI
%token OP_NOR OP_SLL OP_SLLV OP_SRL
%token OP_SRLV OP_SRA OP_SRAV OP_SLT
%token OP_SLTI OP_SLTU OP_SLTIU

%token OP_ADD_S OP_ADD_D OP_SUB_S OP_SUB_D
%token OP_MUL_S OP_MUL_D OP_DIV_S OP_DIV_D
%token OP_ABS_S OP_ABS_D OP_MOV_S OP_MOV_D
%token OP_NEG_S OP_NEG_D
%token OP_CVT_S_D OP_CVT_S_W OP_CVT_D_S OP_CVT_D_W
%token OP_CVT_W_S OP_CVT_W_D
%token OP_C_EQ_S OP_C_EQ_D OP_C_LT_S OP_C_LT_D
%token OP_C_LE_S OP_C_LE_D
%token OP_SQRT_S OP_SQRT_D

%token OP_NOP OP_SYSCALL OP_BREAK OP_LUI
%token OP_MFC OP_MTC OP_RET

%token OP_M1T_TRF OP_M2T_TRF OP_MF_TRF
%token OP_BARRIER OP_ERET OP_MIGRATE

%token MEMBLOCK IFBLOCK ELSEBLOCK WHILEBLOCK DOBLOCK UNTILBLOCK

%token PLUS MINUS MULTIPLY DIVIDE
%token AND OR NOT XOR
%token LSHIFT RSHIFT
%token ADDRESSOF
%token LT GT LTE GTE EQ NEQ
%token ASSIGN

%token LBRACKET RBRACKET
%token LBRACE RBRACE
%token LPAREN RPAREN
%token COLON BANG
%token UNKNOWN

%token <string> LABEL

%token <ivalue> IREG FREG TREG
%token HIREG LOREG PCREG

%token <ivalue> IIMM 
%token <fvalue> FIMM 

%type <ivalue> validireg validfreg validtreg 
%type <mentry> instlist fill inst definition memblock 

%%

/* add the memblocks to a list of instlists */
program: memblock           {
                                add_memblock((mem_entry_t*)$1);
                                /*dump_instlist($1);*/
                            }
    | program memblock      {
                                add_memblock((mem_entry_t*)$2);
                                /*dump_instlist($2);*/
                            }
    | program PCREG ASSIGN IIMM {
                                set_pc($4);
                            }
    | PCREG ASSIGN IIMM     {
                                set_pc($3);
                            }
    ;

memblock: MEMBLOCK LPAREN IIMM RPAREN LBRACE instlist RBRACE { /* at this point, all instructions/etc can get an address */
                                uint32_t current_address = $3;
                                mem_entry_t *list = (mem_entry_t*) $6;
                                mem_entry_t * working = list;
                                while (working){
                                    /* first, if the entry is an instruction, check to make sure
                                       it will get an address aligned to 8 bytes */
                                    if ((working->type == ENTRY_INSTRUCTION) && (current_address & 0x7)){
                                        while (current_address & 0x7)
                                            current_address++;
                                    }
                                    working->address = current_address;
                                    if (working->name && (working->type != ENTRY_DEFINITION)){
                                        /* update symbol table w/ the new address */
                                        symtab_update(working->name,working->address);
                                    }
                                    current_address += working->size;
                                    working = working->next;
                                }
                                $$=list;
                            }
    ;

instlist:                   {$$=NULL;}
    | instlist inst         {$$=(void*)append_inst((mem_entry_t*)$1,(mem_entry_t*)$2);}
    | instlist definition   {$$=(void*)append_inst((mem_entry_t*)$1,(mem_entry_t*)$2);}
    | instlist fill         {$$=(void*)append_inst((mem_entry_t*)$1,(mem_entry_t*)$2);}
    | instlist IFBLOCK LPAREN validireg RPAREN LBRACE instlist RBRACE {
                                mem_entry_t *top_node;
                                mem_entry_t *branch;
                                mem_entry_t *phi_node;
                                /* generate the branch that will test the condition reg */
                                branch = new_instruction(PISA_BEQ); 
                                branch->inst->rsrc1=$4; 
                                branch->inst->rsrc2=0; // compare to $r0
                                /* generate the phi node that will be the target of the branch */
                                phi_node = new_mem_entry(ENTRY_PHI_NODE,0);
                                /* name the phi node */
                                phi_node->name = internal_name();
                                symtab_new(phi_node->name,SYMTAB_MEM);
                                /* set the target of the branch to the phi node name */
                                branch->inst->target_name = strdup(phi_node->name);
                                /* link the branch to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,branch);
                                /* link the second instlist to the branch */
                                top_node = append_inst(top_node,(mem_entry_t*)$7);
                                /* link the phi node to the end of the second instlist */
                                top_node = append_inst(top_node,phi_node);
                                $$=(void*)top_node;
                            }
    | instlist LABEL COLON IFBLOCK LPAREN validireg RPAREN LBRACE instlist RBRACE {
                                mem_entry_t *top_node;
                                mem_entry_t *branch;
                                mem_entry_t *phi_node;
                                /* generate the branch that will test the condition reg */
                                branch = new_instruction(PISA_BEQ);
                                branch->inst->rsrc1=$6;
                                branch->inst->rsrc2=0; // compare to $r0
                                /* name the branch */
                                branch->name = strdup($2);
                                symtab_new(branch->name,SYMTAB_MEM);
                                /* generate the phi node that will be the target of the branch */
                                phi_node = new_mem_entry(ENTRY_PHI_NODE,0);
                                /* name the phi node */
                                phi_node->name = internal_name();
                                symtab_new(phi_node->name,SYMTAB_MEM);
                                /* set the target of the branch to the phi node name */
                                branch->inst->target_name = strdup(phi_node->name);
                                /* link the branch to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,branch);
                                /* link the second instlist to the branch */
                                top_node = append_inst(top_node,(mem_entry_t*)$9);
                                /* link the phi node to the end of the second instlist */
                                top_node = append_inst(top_node,phi_node);
                                $$=(void*)top_node;
                            }
    | instlist IFBLOCK LPAREN validireg RPAREN LBRACE instlist RBRACE ELSEBLOCK LBRACE instlist RBRACE {
                                mem_entry_t *top_node;
                                mem_entry_t *branch;
                                mem_entry_t *jump;
                                mem_entry_t *phi_else;
                                mem_entry_t *phi_done;
                                /* generate branch to else clause */
                                branch = new_instruction(PISA_BEQ); 
                                branch->inst->rsrc1=$4; 
                                branch->inst->rsrc2=0; // compare to $r0
                                /* generate and name phi node for the beginning of else clause */
                                phi_else = new_mem_entry(ENTRY_PHI_NODE,0);
                                phi_else->name = internal_name();
                                symtab_new(phi_else->name,SYMTAB_MEM);
                                /* set the branch target to the phi node name */
                                branch->inst->target_name = strdup(phi_else->name);
                                /* generate jump to skip over else clause */
                                jump = new_instruction(PISA_J);
                                /* generate and name phi node that goes after the else clause */
                                phi_done = new_mem_entry(ENTRY_PHI_NODE,0);
                                phi_done->name = internal_name();
                                symtab_new(phi_done->name,SYMTAB_MEM);
                                /* set the jump target to the phi node name */
                                jump->inst->target_name = strdup(phi_done->name);
                                /* link the branch to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,branch);
                                /* link the second instlist (if clause) to the branch */
                                top_node = append_inst(top_node,(mem_entry_t*)$7);
                                /* link the jump to the end of the second instlist (if clause) */
                                top_node = append_inst(top_node,jump);
                                /* link the else phi node to the end of the jump */
                                top_node = append_inst(top_node,phi_else);
                                /* link the third instlist to the end of the first phi node */
                                top_node = append_inst(top_node,(mem_entry_t*)$11);
                                /* link the second phi node to the end of the third instlist */
                                top_node = append_inst(top_node,phi_done);
                                $$=(void*)top_node;
                            }
    | instlist LABEL COLON IFBLOCK LPAREN validireg RPAREN LBRACE instlist RBRACE ELSEBLOCK LBRACE instlist RBRACE {
                                mem_entry_t *top_node;
                                mem_entry_t *branch;
                                mem_entry_t *jump;
                                mem_entry_t *phi_else;
                                mem_entry_t *phi_done;
                                /* generate branch to else clause */
                                branch = new_instruction(PISA_BEQ);
                                branch->inst->rsrc1=$6;
                                branch->inst->rsrc2=0; // compare to $r0
                                /* name the branch */
                                branch->name = strdup($2);
                                symtab_new(branch->name,SYMTAB_MEM);
                                /* generate and name phi node for the beginning of else clause */
                                phi_else = new_mem_entry(ENTRY_PHI_NODE,0);
                                phi_else->name = internal_name();
                                symtab_new(phi_else->name,SYMTAB_MEM);
                                /* set the branch target to the phi node name */
                                branch->inst->target_name = strdup(phi_else->name);
                                /* generate jump to skip over else clause */
                                jump = new_instruction(PISA_J);
                                /* generate and name phi node that goes after the else clause */
                                phi_done = new_mem_entry(ENTRY_PHI_NODE,0);
                                phi_done->name = internal_name();
                                symtab_new(phi_done->name,SYMTAB_MEM);
                                /* set the jump target to the phi node name */
                                jump->inst->target_name = strdup(phi_done->name);
                                /* link the branch to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,branch);
                                /* link the second instlist (if clause) to the branch */
                                top_node = append_inst(top_node,(mem_entry_t*)$9);
                                /* link the jump to the end of the second instlist (if clause) */
                                top_node = append_inst(top_node,jump);
                                /* link the else phi node to the end of the jump */
                                top_node = append_inst(top_node,phi_else);
                                /* link the third instlist to the end of the first phi node */
                                top_node = append_inst(top_node,(mem_entry_t*)$13);
                                /* link the second phi node to the end of the third instlist */
                                top_node = append_inst(top_node,phi_done);
                                $$=(void*)top_node;
                            }
    | instlist WHILEBLOCK LPAREN validireg RPAREN LBRACE instlist RBRACE {
                                mem_entry_t *top_node;
                                mem_entry_t *top_branch;
                                mem_entry_t *bottom_branch;
                                mem_entry_t *phi_node;
                                char *target;
                                /* generate branch to skip over loop body */
                                top_branch = new_instruction(PISA_BEQ); 
                                top_branch->inst->rsrc1=$4; 
                                top_branch->inst->rsrc2=0; // compare to $r0
                                /* generate and name phi node after loop body */
                                phi_node = new_mem_entry(ENTRY_PHI_NODE,0);
                                phi_node->name = internal_name();
                                symtab_new(phi_node->name,SYMTAB_MEM);
                                /* set the branch target to the phi node name */
                                top_branch->inst->target_name = strdup(phi_node->name);
                                /* generate branch that will target the top of loop body */
                                bottom_branch = new_instruction(PISA_BNE); 
                                bottom_branch->inst->rsrc1=$4; 
                                bottom_branch->inst->rsrc2=0; // compare to $r0
                                /* check the name of the top of the loop body -- create name if necessary */
                                if ($7){
                                    /* find the first non-definition */
                                    mem_entry_t *working = (mem_entry_t*)$7;
                                    while (working){
                                        if (working->type != ENTRY_DEFINITION)
                                            break;
                                        working = working->next;
                                    }
                                    if (working){
                                        /* check for a name -- if none, then name it */
                                        if (!working->name){
                                            working->name = internal_name();
                                            symtab_new(working->name,SYMTAB_MEM);
                                        }
                                        target = working->name;
                                    }
                                    else {
                                        /* loop body was only defs, bottom branch should target itself */
                                        bottom_branch->name = internal_name();
                                        symtab_new(bottom_branch->name,SYMTAB_MEM);
                                        target = bottom_branch->name;
                                    }
                                }
                                else {
                                    /* empty loop body target should be branch itself */
                                    bottom_branch->name = internal_name();
                                    symtab_new(bottom_branch->name,SYMTAB_MEM);
                                    target = bottom_branch->name;
                                }
                                /* set the bottom branch target to the top of the loop body */
                                bottom_branch->inst->target_name = strdup(target);
                                /* link the branch to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,top_branch);
                                /* link the second instlist (loop body) to the end of the branch */
                                top_node = append_inst(top_node,(mem_entry_t*)$7);
                                /* link the bottom branch to the end of the loop body */
                                top_node = append_inst(top_node,bottom_branch);
                                /* link the phi node to the end of the jump */
                                top_node = append_inst(top_node,phi_node);
                                $$=(void*)top_node;
                            }
    | instlist LABEL COLON WHILEBLOCK LPAREN validireg RPAREN LBRACE instlist RBRACE {
                                mem_entry_t *top_node;
                                mem_entry_t *top_branch;
                                mem_entry_t *bottom_branch;
                                mem_entry_t *phi_node;
                                char *target;
                                /* generate branch to skip over loop body */
                                top_branch = new_instruction(PISA_BEQ); 
                                top_branch->inst->rsrc1=$6; 
                                top_branch->inst->rsrc2=0; // compare to $r0
                                /* name the branch */
                                top_branch->name = strdup($2);
                                symtab_new(top_branch->name,SYMTAB_MEM);
                                /* generate and name phi node after loop body */
                                phi_node = new_mem_entry(ENTRY_PHI_NODE,0);
                                phi_node->name = internal_name();
                                symtab_new(phi_node->name,SYMTAB_MEM);
                                /* set the branch target to the phi node name */
                                top_branch->inst->target_name = strdup(phi_node->name);
                                /* generate branch that will target the top of loop body */
                                bottom_branch = new_instruction(PISA_BNE); 
                                bottom_branch->inst->rsrc1=$6; 
                                bottom_branch->inst->rsrc2=0; // compare to $r0
                                /* check the name of the top of the loop body -- create name if necessary */
                                if ($9){
                                    /* find the first non-definition */
                                    mem_entry_t *working = (mem_entry_t*)$9;
                                    while (working){
                                        if (working->type != ENTRY_DEFINITION)
                                            break;
                                        working = working->next;
                                    }
                                    if (working){
                                        /* check for a name -- if none, then name it */
                                        if (!working->name){
                                            working->name = internal_name();
                                            symtab_new(working->name,SYMTAB_MEM);
                                        }
                                        target = working->name;
                                    }
                                    else {
                                        /* loop body was only defs, bottom branch should target itself */
                                        bottom_branch->name = internal_name();
                                        symtab_new(bottom_branch->name,SYMTAB_MEM);
                                        target = bottom_branch->name;
                                    }
                                }
                                else {
                                    /* empty loop body target should be branch itself */
                                    bottom_branch->name = internal_name();
                                    symtab_new(bottom_branch->name,SYMTAB_MEM);
                                    target = bottom_branch->name;
                                }
                                /* set the bottom branch target to the top of the loop body */
                                bottom_branch->inst->target_name = strdup(target);
                                /* link the branch to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,top_branch);
                                /* link the second instlist (loop body) to the end of the branch */
                                top_node = append_inst(top_node,(mem_entry_t*)$9);
                                /* link the bottom branch to the end of the loop body */
                                top_node = append_inst(top_node,bottom_branch);
                                /* link the phi node to the end of the jump */
                                top_node = append_inst(top_node,phi_node);
                                $$=(void*)top_node;
                            }
    | instlist DOBLOCK LBRACE instlist RBRACE WHILEBLOCK LPAREN validireg RPAREN { 
                                mem_entry_t *top_node;
                                mem_entry_t *branch;
                                char *target;
                                /* generate and branch to restart loop body */
                                branch = new_instruction(PISA_BNE); 
                                branch->inst->rsrc1=$8; 
                                branch->inst->rsrc2=0; // compare to $r0
                                /* check the name of the top of the loop body -- create name if necessary */
                                if ($4){
                                    /* find the first non-definition */
                                    mem_entry_t *working = (mem_entry_t*)$4;
                                    while (working){
                                        if (working->type != ENTRY_DEFINITION)
                                            break;
                                        working = working->next;
                                    }
                                    if (working){
                                        /* check for a name -- if none, then name it */
                                        if (!working->name){
                                            working->name = internal_name();
                                            symtab_new(working->name,SYMTAB_MEM);
                                        }
                                        target = working->name;
                                    }
                                    else {
                                        /* loop body was only defs, branch should target itself */
                                        branch->name = internal_name();
                                        symtab_new(branch->name,SYMTAB_MEM);
                                        target = branch->name;
                                    }
                                }
                                else {
                                    /* empty loop body target should be branch itself */
                                    branch->name = internal_name();
                                    symtab_new(branch->name,SYMTAB_MEM);
                                    target = branch->name;
                                }
                                /* set the branch target to the top of the loop body */
                                branch->inst->target_name = strdup(target);
                                /* link the second instlist (loop body) to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,(mem_entry_t*)$4);
                                /* link the branch to the end of the loop body */
                                top_node = append_inst(top_node,branch);
                                $$=(void*)top_node;
                            }
    | instlist LABEL COLON DOBLOCK LBRACE instlist RBRACE WHILEBLOCK LPAREN validireg RPAREN { 
                                mem_entry_t *top_node;
                                mem_entry_t *branch;
                                char *target;
                                /* generate and branch to restart loop body */
                                branch = new_instruction(PISA_BNE); 
                                branch->inst->rsrc1=$10; 
                                branch->inst->rsrc2=0; // compare to $r0
                                /* check the name of the top of the loop body -- create name if necessary */
                                if ($6){
                                    /* find the first non-definition */
                                    mem_entry_t *working = (mem_entry_t*)$6;
                                    while (working){
                                        if (working->type != ENTRY_DEFINITION)
                                            break;
                                        working = working->next;
                                    }
                                    if (working){
                                        /* check for a name -- if none, then name it */
                                        if (!working->name){
                                            working->name = strdup($2);
                                            symtab_new(working->name,SYMTAB_MEM);
                                        }
                                        else {
                                            /* this inst will have two names */
                                            symtab_new($2,SYMTAB_MEM);
                                        }
                                        target = working->name;
                                    }
                                    else {
                                        /* loop body was only defs, branch should target itself */
                                        branch->name = strdup($2);
                                        symtab_new(branch->name,SYMTAB_MEM);
                                        target = branch->name;
                                    }
                                }
                                else {
                                    /* empty loop body target should be branch itself */
                                    branch->name = strdup($2);
                                    symtab_new(branch->name,SYMTAB_MEM);
                                    target = branch->name;
                                }
                                /* set the branch target to the top of the loop body */
                                branch->inst->target_name = strdup(target);
                                /* link the second instlist (loop body) to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,(mem_entry_t*)$6);
                                /* link the branch to the end of the loop body */
                                top_node = append_inst(top_node,branch);
                                $$=(void*)top_node;
                            }
    | instlist UNTILBLOCK LPAREN validireg RPAREN LBRACE instlist RBRACE {
                                mem_entry_t *top_node;
                                mem_entry_t *top_branch;
                                mem_entry_t *bottom_branch;
                                mem_entry_t *phi_node;
                                char *target;
                                /* generate branch to skip over loop body */
                                top_branch = new_instruction(PISA_BNE);
                                top_branch->inst->rsrc1=$4;
                                top_branch->inst->rsrc2=0; // compare to $r0
                                /* generate and name phi node after loop body */
                                phi_node = new_mem_entry(ENTRY_PHI_NODE,0);
                                phi_node->name = internal_name();
                                symtab_new(phi_node->name,SYMTAB_MEM);
                                /* set the branch target to the phi node name */
                                top_branch->inst->target_name = strdup(phi_node->name);
                                /* generate branch that will target the top of loop body */
                                bottom_branch = new_instruction(PISA_BEQ);
                                bottom_branch->inst->rsrc1=$4;
                                bottom_branch->inst->rsrc2=0; // compare to $r0
                                /* check the name of the top of the loop body -- create name if necessary */
                                if ($7){
                                    /* find the first non-definition */
                                    mem_entry_t *working = (mem_entry_t*)$7;
                                    while (working){
                                        if (working->type != ENTRY_DEFINITION)
                                            break;
                                        working = working->next;
                                    }
                                    if (working){
                                        /* check for a name -- if none, then name it */
                                        if (!working->name){
                                            working->name = internal_name();
                                            symtab_new(working->name,SYMTAB_MEM);
                                        }
                                        target = working->name;
                                    }
                                    else {
                                        /* loop body was only defs, bottom branch should target itself */
                                        bottom_branch->name = internal_name();
                                        symtab_new(bottom_branch->name,SYMTAB_MEM);
                                        target = bottom_branch->name;
                                    }
                                }
                                else {
                                    /* empty loop body target should be branch itself */
                                    bottom_branch->name = internal_name();
                                    symtab_new(bottom_branch->name,SYMTAB_MEM);
                                    target = bottom_branch->name;
                                }
                                /* set the bottom branch target to the top of the loop body */
                                bottom_branch->inst->target_name = strdup(target);
                                /* link the branch to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,top_branch);
                                /* link the second instlist (loop body) to the end of the branch */
                                top_node = append_inst(top_node,(mem_entry_t*)$7);
                                /* link the bottom branch to the end of the loop body */
                                top_node = append_inst(top_node,bottom_branch);
                                /* link the phi node to the end of the jump */
                                top_node = append_inst(top_node,phi_node);
                                $$=(void*)top_node;
                            }
    | instlist LABEL COLON UNTILBLOCK LPAREN validireg RPAREN LBRACE instlist RBRACE {
                                mem_entry_t *top_node;
                                mem_entry_t *top_branch;
                                mem_entry_t *bottom_branch;
                                mem_entry_t *phi_node;
                                char *target;
                                /* generate branch to skip over loop body */
                                top_branch = new_instruction(PISA_BNE);
                                top_branch->inst->rsrc1=$6;
                                top_branch->inst->rsrc2=0; // compare to $r0
                                /* name the branch */
                                top_branch->name = strdup($2);
                                symtab_new(top_branch->name,SYMTAB_MEM);
                                /* generate and name phi node after loop body */
                                phi_node = new_mem_entry(ENTRY_PHI_NODE,0);
                                phi_node->name = internal_name();
                                symtab_new(phi_node->name,SYMTAB_MEM);
                                /* set the branch target to the phi node name */
                                top_branch->inst->target_name = strdup(phi_node->name);
                                /* generate branch that will target the top of loop body */
                                bottom_branch = new_instruction(PISA_BEQ);
                                bottom_branch->inst->rsrc1=$6;
                                bottom_branch->inst->rsrc2=0; // compare to $r0
                                /* check the name of the top of the loop body -- create name if necessary */
                                if ($9){
                                    /* find the first non-definition */
                                    mem_entry_t *working = (mem_entry_t*)$9;
                                    while (working){
                                        if (working->type != ENTRY_DEFINITION)
                                            break;
                                        working = working->next;
                                    }
                                    if (working){
                                        /* check for a name -- if none, then name it */
                                        if (!working->name){
                                            working->name = internal_name();
                                            symtab_new(working->name,SYMTAB_MEM);
                                        }
                                        target = working->name;
                                    }
                                    else {
                                        /* loop body was only defs, bottom branch should target itself */
                                        bottom_branch->name = internal_name();
                                        symtab_new(bottom_branch->name,SYMTAB_MEM);
                                        target = bottom_branch->name;
                                    }
                                }
                                else {
                                    /* empty loop body target should be branch itself */
                                    bottom_branch->name = internal_name();
                                    symtab_new(bottom_branch->name,SYMTAB_MEM);
                                    target = bottom_branch->name;
                                }
                                /* set the bottom branch target to the top of the loop body */
                                bottom_branch->inst->target_name = strdup(target);
                                /* link the branch to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,top_branch);
                                /* link the second instlist (loop body) to the end of the branch */
                                top_node = append_inst(top_node,(mem_entry_t*)$9);
                                /* link the bottom branch to the end of the loop body */
                                top_node = append_inst(top_node,bottom_branch);
                                /* link the phi node to the end of the jump */
                                top_node = append_inst(top_node,phi_node);
                                $$=(void*)top_node;
                            }
    | instlist DOBLOCK LBRACE instlist RBRACE UNTILBLOCK LPAREN validireg RPAREN { 
                                mem_entry_t *top_node;
                                mem_entry_t *branch;
                                char *target;
                                /* generate and branch to restart loop body */
                                branch = new_instruction(PISA_BEQ);
                                branch->inst->rsrc1=$8;
                                branch->inst->rsrc2=0; // compare to $r0
                                /* check the name of the top of the loop body -- create name if necessary */
                                if ($4){
                                    /* find the first non-definition */
                                    mem_entry_t *working = (mem_entry_t*)$4;
                                    while (working){
                                        if (working->type != ENTRY_DEFINITION)
                                            break;
                                        working = working->next;
                                    }
                                    if (working){
                                        /* check for a name -- if none, then name it */
                                        if (!working->name){
                                            working->name = internal_name();
                                            symtab_new(working->name,SYMTAB_MEM);
                                        }
                                        target = working->name;
                                    }
                                    else {
                                        /* loop body was only defs, branch should target itself */
                                        branch->name = internal_name();
                                        symtab_new(branch->name,SYMTAB_MEM);
                                        target = branch->name;
                                    }
                                }
                                else {
                                    /* empty loop body target should be branch itself */
                                    branch->name = internal_name();
                                    symtab_new(branch->name,SYMTAB_MEM);
                                    target = branch->name;
                                }
                                /* set the branch target to the top of the loop body */
                                branch->inst->target_name = strdup(target);
                                /* link the second instlist (loop body) to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,(mem_entry_t*)$4);
                                /* link the branch to the end of the loop body */
                                top_node = append_inst(top_node,branch);
                                $$=(void*)top_node;
                            }
    | instlist LABEL COLON DOBLOCK LBRACE instlist RBRACE UNTILBLOCK LPAREN validireg RPAREN { 
                                mem_entry_t *top_node;
                                mem_entry_t *branch;
                                char *target;
                                /* generate and branch to restart loop body */
                                branch = new_instruction(PISA_BEQ);
                                branch->inst->rsrc1=$10;
                                branch->inst->rsrc2=0; // compare to $r0
                                /* check the name of the top of the loop body -- create name if necessary */
                                if ($6){
                                    /* find the first non-definition */
                                    mem_entry_t *working = (mem_entry_t*)$6;
                                    while (working){
                                        if (working->type != ENTRY_DEFINITION)
                                            break;
                                        working = working->next;
                                    }
                                    if (working){
                                        /* check for a name -- if none, then name it */
                                        if (!working->name){
                                            working->name = strdup($2);
                                            symtab_new(working->name,SYMTAB_MEM);
                                        }
                                        else {
                                            /* this inst will have two names */
                                            symtab_new($2,SYMTAB_MEM);
                                        }
                                        target = working->name;
                                    }
                                    else {
                                        /* loop body was only defs, branch should target itself */
                                        branch->name = strdup($2);
                                        symtab_new(branch->name,SYMTAB_MEM);
                                        target = branch->name;
                                    }
                                }
                                else {
                                    /* empty loop body target should be branch itself */
                                    branch->name = strdup($2);
                                    symtab_new(branch->name,SYMTAB_MEM);
                                    target = branch->name;
                                }
                                /* set the branch target to the top of the loop body */
                                branch->inst->target_name = strdup(target);
                                /* link the second instlist (loop body) to the end of the first instlist */
                                top_node = append_inst((mem_entry_t*)$1,(mem_entry_t*)$6);
                                /* link the branch to the end of the loop body */
                                top_node = append_inst(top_node,branch);
                                $$=(void*)top_node;
                            }
    ;

/* TODO check the ranges for immediates and offsets */
/* TODO check for the proper use of $hi/$lo */
/* TODO handle GT, LTE, GTE, EQ, NEQ, etc. */
inst: OP_J IIMM             {
                                mem_entry_t *entry=new_instruction(PISA_J); 
                                entry->inst->target_address=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_J LABEL            {
                                mem_entry_t *entry=new_instruction(PISA_J); 
                                entry->inst->target_name=strdup($2); 
                                $$=(void*)entry;
                            }
    | OP_JAL IIMM           {
                                mem_entry_t *entry=new_instruction(PISA_JAL); 
                                entry->inst->target_address=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_JAL LABEL          {
                                mem_entry_t *entry=new_instruction(PISA_JAL); 
                                entry->inst->target_name=strdup($2); 
                                $$=(void*)entry;
                            }
    | OP_JR validireg       {
                                mem_entry_t *entry=new_instruction(PISA_JR); 
                                entry->inst->rsrc1=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_JALR validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_JALR); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_BEQ validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_BEQ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_BEQ validireg validireg LABEL {
                                mem_entry_t *entry=new_instruction(PISA_BEQ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->inst->target_name=strdup($4); 
                                $$=(void*)entry;
                            }
    | OP_BNE validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_BNE); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_BNE validireg validireg LABEL {
                                mem_entry_t *entry=new_instruction(PISA_BNE); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->inst->target_name=strdup($4); 
                                $$=(void*)entry;
                            }
    | OP_BLEZ validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_BLEZ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_BLEZ validireg LABEL {
                                mem_entry_t *entry=new_instruction(PISA_BLEZ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->target_name=strdup($3); 
                                $$=(void*)entry;
                            }
    | OP_BGTZ validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_BGTZ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_BGTZ validireg LABEL {
                                mem_entry_t *entry=new_instruction(PISA_BGTZ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->target_name=strdup($3); 
                                $$=(void*)entry;
                            }
    | OP_BLTZ validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_BLTZ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_BLTZ validireg LABEL {
                                mem_entry_t *entry=new_instruction(PISA_BLTZ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->target_name=strdup($3); 
                                $$=(void*)entry;
                            }
    | OP_BGEZ validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_BGEZ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_BGEZ validireg LABEL {
                                mem_entry_t *entry=new_instruction(PISA_BGEZ); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->target_name=strdup($3); 
                                $$=(void*)entry;
                            }
    | OP_BCF IIMM           {
                                mem_entry_t *entry=new_instruction(PISA_BC1F); 
                                entry->inst->imm=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_BCF LABEL          {
                                mem_entry_t *entry=new_instruction(PISA_BC1F); 
                                entry->inst->target_name=strdup($2);
                                $$=(void*)entry;
                            }
    | OP_BCT IIMM           {
                                mem_entry_t *entry=new_instruction(PISA_BC1T); 
                                entry->inst->imm=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_BCT LABEL          {
                                mem_entry_t *entry=new_instruction(PISA_BC1T); 
                                entry->inst->target_name=strdup($2);
                                $$=(void*)entry;
                            }
    | OP_LB validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LB_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LB validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_LB_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LB validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LB_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LB validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_LB_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LBU validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LBU_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LBU validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_LBU_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LBU validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LBU_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LBU validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_LBU_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LH validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LH_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LH validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_LH_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LH validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LH_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LH validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_LH_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LHU validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LHU_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LHU validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_LHU_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LHU validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LHU_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LHU validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_LHU_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LW validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LW_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LW validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_LW_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LW validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_LW_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LW validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_LW_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DLW validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_DLW_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DLW validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_DLW_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DLW validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_DLW_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DLW validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_DLW_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_L_S validfreg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_L_S_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_L_S validfreg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_L_S_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_L_S validfreg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_L_S_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_L_S validfreg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_L_S_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_L_D validfreg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_L_D_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_L_D validfreg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_L_D_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_L_D validfreg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_L_D_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_L_D validfreg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_L_D_I); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_LWL                { /* TODO */
                                yyerror("LWL not yet implemented");
                                $$=(void*)NULL;
                            }
    | OP_LWR                { /* TODO */
                                yyerror("LWR not yet implemented");
                                $$=(void*)NULL;
                            }
    | OP_SB validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_SB_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SB validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SB_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SB validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_SB_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SB validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SB_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SH validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_SH_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SH validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SH_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SH validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_SH_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SH validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SH_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SW validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_SW_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SW validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SW_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SW validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_SW_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SW validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SW_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DSW validireg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_DSW_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DSW validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_DSW_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DSW validireg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_DSW_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DSW validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_DSW_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DSZ IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_DSZ_D); 
                                entry->inst->rbase=$4; 
                                entry->inst->imm=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DSZ validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_DSZ_D); 
                                entry->inst->rbase=$2; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DSZ validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_DSZ_I); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DSZ validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_DSZ_I); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_S_S validfreg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_S_S_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_S_S validfreg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_S_S_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_S_S validfreg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_S_S_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_S_S validfreg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_S_S_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_S_D validfreg IIMM LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_S_D_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_S_D validfreg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_S_D_D); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rbase=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_S_D validfreg validireg LBRACKET validireg RBRACKET {
                                mem_entry_t *entry=new_instruction(PISA_S_D_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_S_D validfreg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_S_D_I); 
                                entry->inst->rsrc0=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SWL                { /* TODO */
                                yyerror("SWL not yet implemented");
                                $$=(void*)NULL;
                            }
    | OP_SWR                { /* TODO */
                                yyerror("SWR not yet implemented");
                                $$=(void*)NULL;
                            }
    | OP_ADD validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_ADD); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg PLUS validireg {
                                mem_entry_t *entry=new_instruction(PISA_ADD); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_ADDI validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_ADDI); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg PLUS IIMM {
                                mem_entry_t *entry=new_instruction(PISA_ADDI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN IIMM PLUS validireg {
                                mem_entry_t *entry=new_instruction(PISA_ADDI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_ADDU validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_ADDU); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_ADDIU validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_ADDIU); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SUB validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SUB); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg MINUS validireg {
                                mem_entry_t *entry=new_instruction(PISA_SUB); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg MINUS IIMM {
                                mem_entry_t *entry=new_instruction(PISA_ADDI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=0-$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN IIMM MINUS validireg {
                                mem_entry_t *entry=new_instruction(PISA_ADDI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$5; 
                                entry->inst->imm=0-$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN MINUS validireg {
                                mem_entry_t *entry=new_instruction(PISA_SUB); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=0; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SUBU validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SUBU); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MULT validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_MULT); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg MULTIPLY validireg {
                                mem_entry_t *entry=new_instruction(PISA_MULT); 
                                if ($1==PISA_HI || $1==PISA_LO){ 
                                    entry->inst->rdst=$1; 
                                    entry->inst->rsrc1=$3; 
                                    entry->inst->rsrc2=$5; 
                                    entry->status = ENTRY_COMPLETE;
                                }else{
                                    yyerror("The result of multiply must be assigned to either $hi or $lo");
                                } 
                                $$=(void*)entry;
                            }
    | OP_MULTU validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_MULTU); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DIV validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_DIV); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg DIVIDE validireg {
                                mem_entry_t *entry=new_instruction(PISA_DIV); 
                                if ($1==PISA_HI || $1==PISA_LO){ 
                                    entry->inst->rdst=$1; 
                                    entry->inst->rsrc1=$3; 
                                    entry->inst->rsrc2=$5; 
                                    entry->status = ENTRY_COMPLETE;
                                }else{
                                    yyerror("The result of divide must be assigned to either $hi or $lo");
                                } 
                                $$=(void*)entry;
                            }
    | OP_DIVU validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_DIVU); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MFHI validireg     {
                                mem_entry_t *entry=new_instruction(PISA_MFHI); 
                                entry->inst->rdst=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MTHI validireg     {
                                mem_entry_t *entry=new_instruction(PISA_MTHI); 
                                entry->inst->rsrc1=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MFLO validireg     {
                                mem_entry_t *entry=new_instruction(PISA_MFLO); 
                                entry->inst->rdst=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MTLO validireg     {
                                mem_entry_t *entry=new_instruction(PISA_MTLO); 
                                entry->inst->rsrc1=$2; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg {
                                mem_entry_t *entry=NULL;
                                if ($1==PISA_HI){
                                    if (($3==PISA_HI) || ($3==PISA_LO))
                                        yyerror("Cannot move between $hi and $lo directly (you must use two instructions).");
                                    else{
                                        entry=new_instruction(PISA_MTHI); 
                                        entry->inst->rsrc1=$3;
                                    }
                                }
                                else if ($1==PISA_LO){
                                    if (($3==PISA_HI) || ($3==PISA_LO))
                                        yyerror("Cannot move between $hi and $lo directly (you must use two instructions).");
                                    else{
                                        entry=new_instruction(PISA_MTLO); 
                                        entry->inst->rsrc1=$3;
                                    }
                                }
                                else{
                                    if ($3==PISA_HI){
                                        entry=new_instruction(PISA_MFHI); 
                                        entry->inst->rdst=$1;
                                    }
                                    else if ($3==PISA_LO){
                                        entry=new_instruction(PISA_MFLO); 
                                        entry->inst->rdst=$1;
                                    }
                                    else {
                                        entry=new_instruction(PISA_ADDI); 
                                        entry->inst->rdst=$1; 
                                        entry->inst->rsrc1=$3; 
                                        entry->inst->imm=0;
                                    }
                                } 
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_AND validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_AND); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg AND validireg {
                                mem_entry_t *entry=new_instruction(PISA_AND); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_ANDI validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_ANDI); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg AND IIMM {
                                mem_entry_t *entry=new_instruction(PISA_ANDI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN IIMM AND validireg {
                                mem_entry_t *entry=new_instruction(PISA_ANDI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_OR validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_OR); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg OR validireg {
                                mem_entry_t *entry=new_instruction(PISA_OR); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_ORI validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_ORI); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg OR IIMM {
                                mem_entry_t *entry=new_instruction(PISA_ORI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN IIMM OR validireg {
                                mem_entry_t *entry=new_instruction(PISA_ORI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_XOR validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_XOR); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg XOR validireg {
                                mem_entry_t *entry=new_instruction(PISA_XOR); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_XORI validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_XORI); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg XOR IIMM {
                                mem_entry_t *entry=new_instruction(PISA_XORI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN IIMM XOR validireg {
                                mem_entry_t *entry=new_instruction(PISA_XORI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_NOR validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_NOR); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN NOT validireg {
                                mem_entry_t *entry=new_instruction(PISA_NOR); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$4; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN NOT IIMM {
                                mem_entry_t *entry=NULL; 
                                if ((~((uint32_t)$4)) & 0xffff0000){
                                    /* upper two bytes */
                                    entry=new_instruction(PISA_LUI);
                                    entry->inst->rdst=$1;
                                    entry->inst->imm=((~((uint32_t)$4))>>16); 
                                    entry->status = ENTRY_COMPLETE;
                                    if ((~((uint32_t)$4)) & 0x0000ffff){ /* only do lower two bytes if needed */
                                        mem_entry_t *entry2=new_instruction(PISA_ORI);
                                        entry2->inst->rdst=$1;
                                        entry2->inst->rsrc1=$1;
                                        entry2->inst->imm=((~((uint32_t)$4))&0xffff);
                                        entry2->status = ENTRY_COMPLETE;
                                        entry=append_inst(entry,entry2);
                                    }
                                }
                                else{
                                    /* only an ADDI */
                                    entry=new_instruction(PISA_ADDI);
                                    entry->inst->rdst=$1;
                                    entry->inst->rsrc1=0; /* just addi to $r0 */
                                    entry->inst->imm=(~((uint32_t)$4));
                                    entry->status = ENTRY_COMPLETE;
                                }
                                $$=(void*)entry;
                            }
    | OP_SLL validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SLL); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg LSHIFT IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SLL); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SLLV validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SLLV); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg LSHIFT validireg {
                                mem_entry_t *entry=new_instruction(PISA_SLLV); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SRL validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SRL); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg RSHIFT IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SRL); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SRLV validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SRLV); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg RSHIFT validireg {
                                mem_entry_t *entry=new_instruction(PISA_SRLV); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SRA validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SRA); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SRAV validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SRAV); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SLT validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SLT); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg LT validireg {
                                mem_entry_t *entry=new_instruction(PISA_SLT); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SLTI validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SLTI); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg LT IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SLTI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN IIMM GT validireg {
                                mem_entry_t *entry=new_instruction(PISA_SLTI); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$5; 
                                entry->inst->imm=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg GT validireg {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator > not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg GT IIMM {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator > not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN IIMM LT validireg {
                                mem_entry_t *entry=NULL; 
                                yyerror("this version of operator < not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg LTE validireg {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator <= not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg LTE IIMM {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator <= not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg GTE validireg {
                                mem_entry_t *top;
                                mem_entry_t *entry=new_instruction(PISA_SLT);
                                mem_entry_t *entry2;
                                mem_entry_t *entry3;
                                entry->inst->rdst=$1;
                                entry->inst->rsrc1=$3;
                                entry->inst->rsrc2=$5;
                                entry->status = ENTRY_COMPLETE;
                                entry2=new_instruction(PISA_NOR);
                                entry2->inst->rdst=$1;
                                entry2->inst->rsrc1=$1;
                                entry2->inst->rsrc2=$1;
                                entry2->status = ENTRY_COMPLETE;
                                entry3=new_instruction(PISA_ANDI);
                                entry3->inst->rdst=$1;
                                entry3->inst->rsrc1=$1;
                                entry3->inst->imm=0xfffffffe;
                                entry3->status = ENTRY_COMPLETE;
                                top=append_inst(entry,entry2);
                                top=append_inst(top,entry3);
                                $$=(void*)top;
                            }
    | validireg ASSIGN validireg GTE IIMM {
                                mem_entry_t *top;
                                mem_entry_t *entry=new_instruction(PISA_SLT);
                                mem_entry_t *entry2;
                                mem_entry_t *entry3;
                                entry->inst->rdst=$1;
                                entry->inst->rsrc1=$3;
                                entry->inst->imm=$5;
                                entry->status = ENTRY_COMPLETE;
                                entry2=new_instruction(PISA_NOR);
                                entry2->inst->rdst=$1;
                                entry2->inst->rsrc1=$1;
                                entry2->inst->rsrc2=$1;
                                entry2->status = ENTRY_COMPLETE;
                                entry3=new_instruction(PISA_ANDI);
                                entry3->inst->rdst=$1;
                                entry3->inst->rsrc1=$1;
                                entry3->inst->imm=0xfffffffe;
                                entry3->status = ENTRY_COMPLETE;
                                top=append_inst(entry,entry2);
                                top=append_inst(top,entry3);
                                $$=(void*)top;
                            }
    | validireg ASSIGN validireg EQ validireg {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator == not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg EQ IIMM {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator == not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN IIMM EQ validireg {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator == not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg NEQ validireg {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator != not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN validireg NEQ IIMM {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator != not yet implemented"); 
                                $$=(void*)entry;
                            }
    | validireg ASSIGN IIMM NEQ validireg {
                                mem_entry_t *entry=NULL; 
                                yyerror("operator != not yet implemented"); 
                                $$=(void*)entry;
                            }
    | OP_SLTU validireg validireg validireg {
                                mem_entry_t *entry=new_instruction(PISA_SLTU); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SLTIU validireg validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_SLTIU); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->imm=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_ADD_S validfreg validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_ADD_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validfreg ASSIGN validfreg PLUS validfreg {
                                mem_entry_t *entry=new_instruction(PISA_ADD_S); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_ADD_D validfreg validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_ADD_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SUB_S validfreg validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_SUB_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validfreg ASSIGN validfreg MINUS validfreg {
                                mem_entry_t *entry=new_instruction(PISA_SUB_S); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SUB_D validfreg validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_SUB_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MUL_S validfreg validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_MUL_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validfreg ASSIGN validfreg MULTIPLY validfreg {
                                mem_entry_t *entry=new_instruction(PISA_MUL_S); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MUL_D validfreg validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_MUL_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DIV_S validfreg validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_DIV_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validfreg ASSIGN validfreg DIVIDE validfreg {
                                mem_entry_t *entry=new_instruction(PISA_DIV_S); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$5; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_DIV_D validfreg validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_DIV_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->inst->rsrc2=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_ABS_S validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_ABS_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_ABS_D validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_ABS_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MOV_S validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_MOV_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validfreg ASSIGN validfreg {
                                mem_entry_t *entry=new_instruction(PISA_MOV_S); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MOV_D validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_MOV_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_NEG_S validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_NEG_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | validfreg ASSIGN MINUS validfreg {
                                mem_entry_t *entry=new_instruction(PISA_NEG_S); 
                                entry->inst->rdst=$1; 
                                entry->inst->rsrc1=$4; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_NEG_D validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_NEG_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_CVT_S_D validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_CVT_S_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_CVT_S_W validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_CVT_S_W); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_CVT_D_S validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_CVT_D_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_CVT_D_W validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_CVT_D_W); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_CVT_W_S validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_CVT_W_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_CVT_W_D validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_CVT_W_D); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_C_EQ_S validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_C_EQ_S); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_C_EQ_D validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_C_EQ_D); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_C_LT_S validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_C_LT_S); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_C_LT_D validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_C_LT_D); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_C_LE_S validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_C_LE_S); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_C_LE_D validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_C_LE_D); 
                                entry->inst->rsrc1=$2; 
                                entry->inst->rsrc2=$3; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_SQRT_S validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_SQRT_S); 
                                entry->inst->rdst=$2; 
                                entry->inst->rsrc1=$3; 
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_SQRT_D validfreg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_SQRT_D);
                                entry->inst->rdst=$2;
                                entry->inst->rsrc1=$3;
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_NOP                {
                                mem_entry_t *entry=new_instruction(PISA_NOP); 
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_SYSCALL            {
                                mem_entry_t *entry=new_instruction(PISA_SYSCALL);
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_BREAK IIMM         {
                                mem_entry_t *entry=new_instruction(PISA_BREAK);
                                entry->inst->imm=$2;
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_LUI validireg IIMM {
                                mem_entry_t *entry=new_instruction(PISA_LUI);
                                entry->inst->rdst=$2;
                                entry->inst->imm=$3;
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | validireg ASSIGN ADDRESSOF LABEL {
                                mem_entry_t *top;
                                mem_entry_t *upper_entry=new_instruction(PISA_LUI);
                                mem_entry_t *lower_entry=new_instruction(PISA_ORI);
                                upper_entry->inst->rdst=$1;
                                upper_entry->inst->target_name = strdup($4);
                                lower_entry->inst->rdst=$1;
                                lower_entry->inst->rsrc1=$1;
                                lower_entry->inst->target_name = strdup($4);
                                top = append_inst(upper_entry,lower_entry);
                                $$=(void*)top;
                            }
    | validireg ASSIGN IIMM {
                                mem_entry_t *entry=NULL; 
                                if ($3 & 0xffff0000){
                                    /* upper two bytes */
                                    entry=new_instruction(PISA_LUI);
                                    entry->inst->rdst=$1;
                                    entry->inst->imm=($3>>16); 
                                    entry->status = ENTRY_COMPLETE;
                                    if ($3 & 0x0000ffff){ /* only do lower two bytes if needed */
                                        mem_entry_t *entry2=new_instruction(PISA_ORI);
                                        entry2->inst->rdst=$1;
                                        entry2->inst->rsrc1=$1;
                                        entry2->inst->imm=($3&0xffff);
                                        entry2->status = ENTRY_COMPLETE;
                                        entry=append_inst(entry,entry2);
                                    }
                                }
                                else{
                                    /* only an ORI */
                                    entry=new_instruction(PISA_ORI);
                                    entry->inst->rdst=$1;
                                    entry->inst->rsrc1=0; /* just addi to $r0 */
                                    entry->inst->imm=$3;
                                    entry->status = ENTRY_COMPLETE;
                                }
                                $$=(void*)entry;
                            }
    | OP_RET                {
                                mem_entry_t *entry=new_instruction(PISA_JR); 
                                entry->inst->rsrc1=31; 
                                entry->status = ENTRY_COMPLETE; 
                                $$=(void*)entry;
                            }
    | OP_MFC validireg validfreg {
                                mem_entry_t *entry=new_instruction(PISA_MFC1);
                                entry->inst->rdst=$2;
                                entry->inst->rsrc1=$3;
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_MTC validfreg validireg {
                                mem_entry_t *entry=new_instruction(PISA_MTC1);
                                entry->inst->rdst=$2;
                                entry->inst->rsrc1=$3;
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_M1T_TRF validireg  {
                                mem_entry_t *entry=new_instruction(PISA_M1T_TRF);
                                entry->inst->rsrc1=$2;
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_M2T_TRF validireg validireg { 
                                mem_entry_t *entry=new_instruction(PISA_M2T_TRF);
                                entry->inst->rsrc1=$2;
                                entry->inst->rsrc2=$3;
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_MF_TRF validtreg   {
                                mem_entry_t *entry=new_instruction(PISA_MF_TRF);
                                entry->inst->rdst=$2;
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_BARRIER            {
                                mem_entry_t *entry=new_instruction(PISA_BARRIER);
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_ERET               {
                                mem_entry_t *entry=new_instruction(PISA_ERET);
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    | OP_MIGRATE            {
                                mem_entry_t *entry=new_instruction(PISA_MIGRATE);
                                entry->status = ENTRY_COMPLETE;
                                $$=(void*)entry;
                            }
    ;

validireg : IREG            {
                                if ($1 > 31) {
                                    yyerror("Bad int register number");
                                } 
                                else {
                                    $$ = $1;
                                }
                            }
    | HIREG                 {$$ = PISA_HI;}
    | LOREG                 {$$ = PISA_LO;}
    | LABEL                 {
                                if ((symtab_lookup($1)!=-1)&&(symtab_type($1)==SYMTAB_IREG)){
                                    $$ = symtab_lookup($1);
                                }
                                else{
                                    char buff[1000];
                                    sprintf(buff,"Label \"%s\" failed, either the label has not "
                                                 "been defined, or the label type is not an integer register.",$1);
                                    yyerror(buff);
                                }
                            }
    ;


validfreg : FREG            {if ($1 > 31) {yyerror("Bad fp register number");} else {$$ = $1;}}
    ;

 /*validfreg : FREG            {if ($1 > 31) {yyerror("Bad fp register number");} else {$$ = $1;}}
    | LABEL                 {
                                if ((symtab_lookup($1)!=-1)&&(symtab_type($1)==SYMTAB_FREG)){
                                    $$ = symtab_lookup($1);
                                }
                                else{
                                    char buff[1000];
                                    sprintf(buff,"Label \"%s\" failed, either the label has not "
                                                 "been defined, or the label type is not a floating-point register.",$1);
                                    yyerror(buff);
                                }
                            }
    ;*/


validtreg : TREG            {if ($1 > 31) {yyerror("Bad trf register number");} else {$$ = $1;}}
    ;

/*validtreg : TREG            {if ($1 > 31) {yyerror("Bad trf register number");} else {$$ = $1;}}
    | LABEL                 {
                                if ((symtab_lookup($1)!=-1)&&(symtab_type($1)==SYMTAB_TREG)){
                                    $$ = symtab_lookup($1);
                                }
                                else{
                                    char buff[1000];
                                    sprintf(buff,"Label \"%s\" failed, either the label has not "
                                                 "been defined, or the label type is not a TRF register.",$1);
                                    yyerror(buff);
                                }
                            }
    ;*/

fill : BANG IIMM            {mem_entry_t *entry = new_mem_entry(ENTRY_IDATA,4); entry->ivalue=$2; $$=(void*)entry;}
    | BANG FIMM             {mem_entry_t *entry = new_mem_entry(ENTRY_FDATA,4); entry->fvalue=$2; $$=(void*)entry;}
    ;

definition : LABEL COLON validireg {
                                mem_entry_t *entry = new_mem_entry(ENTRY_DEFINITION,0); 
                                symtab_new($1,SYMTAB_IREG);
                                symtab_update($1,$3); 
                                entry->name = strdup($1);
                                $$=(void*)entry;
                            }
    | LABEL COLON validfreg {
                                mem_entry_t *entry = new_mem_entry(ENTRY_DEFINITION,0); 
                                symtab_new($1,SYMTAB_FREG);
                                symtab_update($1,$3); 
                                entry->name = strdup($1);
                                $$=(void*)entry;
                            }
    | LABEL COLON validtreg {
                                mem_entry_t *entry = new_mem_entry(ENTRY_DEFINITION,0); 
                                symtab_new($1,SYMTAB_TREG);
                                symtab_update($1,$3);
                                entry->name = strdup($1);
                                $$=(void*)entry;
                            }
    | LABEL COLON inst      { /* not marked as an ENTRY_DEFINITION -- being an ENTRY_INSTRUCTION over-rides this */
                                symtab_new($1,SYMTAB_MEM);
                                ((mem_entry_t*)$3)->name = strdup($1);
                                $$=$3;
                            }
    | LABEL COLON fill      { /* ditto for ENTRY_IDATA or ENTRY_FDATA */
                                symtab_new($1,SYMTAB_MEM);
                                ((mem_entry_t*)$3)->name = strdup($1);
                                $$=$3;
                            }
    ;

%%

int yydebug = 1;
extern int yylineno; /* from lexer */
char * current_file;

int main(int argc, char *argv[]){
    int i;
    BOOL valid_input = TRUE;
    BOOL flat_mem = FALSE;
    BOOL scratchpad_mem = FALSE;
    BOOL fpga_mem = FALSE;
    int input_file_count = 0;
    char *input_files[100];
    char *output_file;
    BOOL user_named_output = FALSE;
    BOOL dump_debug = FALSE;

    for (i=1;i<argc;i++){
        if (argv[i][0] == '-'){
            if (strcmp(argv[i],"-flat") == 0)
                flat_mem = TRUE;
            else if (strcmp(argv[i],"-scratchpad") == 0)
                scratchpad_mem = TRUE;
            else if (strcmp(argv[i],"-fpga") == 0)
                fpga_mem = TRUE;
            else if (strcmp(argv[i],"-checking") == 0)
                dump_debug = TRUE;
            else if (strcmp(argv[i],"-out") == 0){
                user_named_output = TRUE;
                if (((i+1)<argc) && (argv[i+1][0] != '-')){
                    output_file = strdup(argv[i+1]);
                    i++;
                }
                else
                    valid_input = FALSE;
            }
            else {
                valid_input = FALSE;
            }
        }
        else {
            input_files[input_file_count++] = strdup(argv[i]);
        }
    }

    if (input_file_count == 0) valid_input = FALSE;
    if (!(flat_mem || scratchpad_mem || fpga_mem)) flat_mem = TRUE;
    if (!user_named_output) output_file = strdup("a");

    if (!valid_input){
        fprintf(stderr,"usage: %s [flags] <file...>\n\n",argv[0]);
        fprintf(stderr,"flags:\n");
        fprintf(stderr,"       -flat            Output should be written to a\n");
        fprintf(stderr,"                        checkpoint (non-debug cores).  This\n");
        fprintf(stderr,"                        is the default.\n");
        fprintf(stderr,"       -scratchpad      Output should be written to two files,\n");
        fprintf(stderr,"                        one for the I-scratchpad and one for the\n");
        fprintf(stderr,"                        D-scratchpad (debug core) which can be read\n");
        fprintf(stderr,"                        in the testbench using the readmemh function.\n");
        fprintf(stderr,"                        This option requires that you have mem blocks\n");
        fprintf(stderr,"                        with addresses in the range of 0-256 for the\n");
        fprintf(stderr,"                        I-scratchpad, and 1024-1280 for the D-scratchpad.\n");
        fprintf(stderr,"       -fpga            Output should be written to three files, \n");
        fprintf(stderr,"                        in the format required by the fpga testbench,\n");
        fprintf(stderr,"                        one file for mem, pc, and regs (which is always\n");
        fprintf(stderr,"                        zeros).\n");
        fprintf(stderr,"       -out <file>      Output filenames will start with <file>.\n");
        fprintf(stderr,"                        The default is \"a\".\n");
        fprintf(stderr,"       -checking        Prints debug info (encodings, addresses, etc) \n");
        fprintf(stderr,"                        for parsed program to stdout.\n");
        exit(1);
    }
    else {
        srandom(1);
        for (i=0;i<input_file_count;i++){
            FILE *fd = fopen(input_files[i],"r");
            if (fd){
                current_file = input_files[i];
                yyrestart(fd);
                yylineno = 1;
                yyparse();
            }
            else{
                fprintf(stderr,"Could not open source file: %s\n",input_files[i]);
                exit(1);
            }
            fclose(fd);
        }

        current_file = strdup("<<global>>");
        yylineno = -1;

        check_mem_bounds(); /* makes sure mem() blocks don't have overlapping addresses */
        calculate_offsets(); /* calculate the offset field for any instruction that used a labeled target */
        encode_instructions(); /* do the actual encoding of instructions */

        if (dump_debug){
            print_memlist_info();
            dump_symtab();
        }

        if (flat_mem){
            char *buff = (char*) malloc(sizeof(char)*1000);
            sprintf(buff,"%s.chkpt",output_file);
            write_flat(buff);
            free (buff);
        }

        if (fpga_mem){
            char *mbuff = (char*) malloc(sizeof(char)*1000);
            char *pbuff = (char*) malloc(sizeof(char)*1000);
            char *rbuff = (char*) malloc(sizeof(char)*1000);
            sprintf(mbuff,"%s.mem.init",output_file);
            sprintf(pbuff,"%s.pc.init",output_file);
            sprintf(rbuff,"%s.rf.init",output_file);
            write_fpga(mbuff,pbuff,rbuff);
            free (mbuff);
            free (pbuff);
            free (rbuff);
        }

        if (scratchpad_mem){
            char *ibuff = (char*) malloc(sizeof(char)*1000);
            char *dbuff = (char*) malloc(sizeof(char)*1000);
            check_scratchpad();
            sprintf(ibuff,"%s.i.dat",output_file);
            sprintf(dbuff,"%s.d.dat",output_file);
            write_scratchpads(ibuff,dbuff);
            free (ibuff);
            free (dbuff);
        }
    }

    return 0;
}

int yyerror(char *s){
    fprintf(stderr, "error: %s\n\tfile: %s\n\tline: %d\n", s, current_file, yylineno);
    exit(1);
}
