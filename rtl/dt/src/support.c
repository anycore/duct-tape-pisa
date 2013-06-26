#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include "dt.tab.h"
#include "support.h"

uint32_t pc = 0;


mem_entry_t * new_mem_entry(type_t type, uint32_t size){
    mem_entry_t * new_entry = (mem_entry_t *) malloc(sizeof(mem_entry_t));
    new_entry->status = ENTRY_INCOMPLETE;
    new_entry->type = type;
    new_entry->name = NULL;
    new_entry->address = 0;
    new_entry->size = size;
    new_entry->inst = NULL;
    new_entry->ivalue = 0;
    new_entry->next = NULL;

    return new_entry;
}

mem_entry_t * new_instruction(uint32_t opcode){
    instruction_t * new_inst = (instruction_t*)malloc(sizeof(instruction_t));
    mem_entry_t * new_entry = (mem_entry_t*)malloc(sizeof(mem_entry_t));

    new_inst->opcode = opcode;
    new_inst->rdst = 0;
    new_inst->rsrc1 = 0;
    new_inst->rsrc2 = 0;
    new_inst->imm = 0;
    new_inst->target_name = NULL;

    new_entry->status = ENTRY_INCOMPLETE;
    new_entry->type = ENTRY_INSTRUCTION;
    new_entry->name = NULL;
    new_entry->address = 0;
    new_entry->size = 8;
    new_entry->inst = new_inst;
    new_entry->encoding = 0;
    new_entry->next = NULL;

    return new_entry;
}

mem_entry_t *append_inst(mem_entry_t *list, mem_entry_t *inst){
    if (list){
        mem_entry_t *working = list;
        while (working){
            if (working->next == NULL){
                /* found the end of the existing list */
                working->next = inst;
                break;
            }
            working = working->next;
        }
        return list;
    }
    else{
        return inst;
    }
}

/* this is used to generate random labels/names for the phi nodes */
char *internal_name(){
    int i;
    char *retval = (char*)malloc(sizeof(char)*20);
    sprintf(retval,"__internal_");
    for (i=11;i<20;i++){
        retval[i] = 'a' + (random()%26); // generates a random character from a-z
    }
    return retval;
}


memblock_list_t *block_list = NULL;

void add_memblock(mem_entry_t* list){
    mem_entry_t *working;
    memblock_list_t *new_node = (memblock_list_t*)malloc(sizeof(memblock_list_t));

    new_node->head = list;
    new_node->next = NULL;
    if (list){
        working = list;
        while (working){
            if (working->next == NULL)
                break;
            working = working->next;
        }
        if (list->address < working->address){
            /* the typical case where there is at least one instruction or fill in a mem() block */
            new_node->min_address = list->address;
            new_node->max_address = (working->address + working->size) - 1;
        }
        else if (list->address == working->address){
            /* the rare case that a mem() block has only definitions */
            new_node->min_address = list->address;
            new_node->max_address = working->address;
        }
        else {
            /* the case where the last element has a lower address than the first 
               cannot happen normally -- something is seriously screwed up */
            printf("list: %x working: %x\n",list->address,working->address);
            yyerror("mem() block addresses are corrupt");
        }
    }
    else {
        /* another rare case in which the list was empty -- 
           must be an empty mem() block in the source code */
        new_node->min_address = 0;
        new_node->max_address = 0;
    }

    if (block_list){
        memblock_list_t *working_list = block_list;
        while (working_list){
            if (working_list->next == NULL)
                break;
            working_list = working_list->next;
        }
        working_list->next = new_node;
    }
    else {
        block_list = new_node;
    }
}

void check_mem_bounds(){
    memblock_list_t *check = block_list;

    while (check){
        memblock_list_t *working = block_list;
        while (working){
            if ((check != working) && (check->min_address != check->max_address) && (working->min_address != working->max_address)){
                if (check->min_address <= working->min_address){
                    if (check->max_address >= working->min_address){
                        char buff[200];
                        sprintf(buff,"The memory block starting at address 0x%x "
                                     "overlaps the memory block starting at address 0x%x",
                                     check->min_address,working->min_address);
                        yyerror(buff);
                    }
                }
            }
            working = working->next;
        }
        check = check->next;
    }
}

void calculate_offsets(){
    memblock_list_t *list = block_list;

    while (list){
        mem_entry_t *working = list->head;
        while (working){
            if ((working->type == ENTRY_INSTRUCTION) && (working->status == ENTRY_INCOMPLETE)){
                char buff[100];
                int target_address = symtab_lookup(working->inst->target_name);
                if (target_address < 0){
                    sprintf(buff,"Symbol table lookup failed on label \"%s\" -- name not found.",
                                 working->inst->target_name);
                    yyerror(buff);
                }
                else if (symtab_type(working->inst->target_name) != SYMTAB_MEM) {
                    sprintf(buff,"Symbol table lookup failed on label \"%s\" --"
                                 " label refers to a register.",
                                 working->inst->target_name);
                    yyerror(buff);
                }
                else {
                    if ((working->inst->opcode == PISA_J) || 
                        (working->inst->opcode == PISA_JAL)){
                        working->inst->target_address = target_address;
                        working->status = ENTRY_COMPLETE;
                    }
                    else if ((working->inst->opcode == PISA_BEQ) ||
                             (working->inst->opcode == PISA_BNE) ||
                             (working->inst->opcode == PISA_BLEZ) ||
                             (working->inst->opcode == PISA_BGTZ) ||
                             (working->inst->opcode == PISA_BLTZ) ||
                             (working->inst->opcode == PISA_BGEZ) ||
                             (working->inst->opcode == PISA_BC1F) ||
                             (working->inst->opcode == PISA_BC1T)){
                        working->inst->imm = (target_address - (working->address + 8)) & 0x3ffff;
                        working->status = ENTRY_COMPLETE;
                    }
                    else if (working->inst->opcode == PISA_LUI){
                        /* from the address-of operator */
                        working->inst->imm = (target_address >> 16) & 0xffff;
                        working->status = ENTRY_COMPLETE;
                    }
                    else if (working->inst->opcode == PISA_ORI){
                        /* from the address-of operator */
                        working->inst->imm = target_address & 0xffff;
                        working->status = ENTRY_COMPLETE;
                    }
                    else {
                        sprintf(buff,"Unexpected incomplete instruction at address 0x%x",
                                     working->address);
                        yyerror(buff);
                    }
                }
            }
            working = working->next;
        }
        list = list->next;
    }
}

void encode_instructions(){
    memblock_list_t *list = block_list;

    while (list){
        mem_entry_t *working = list->head;
        while (working){
            if (working->type == ENTRY_INSTRUCTION){
                working->encoding = encode_instruction(working->inst);
            }
            working = working->next;
        }
        list = list->next;
    }
}

void check_scratchpad(){
    int num_lists = 0;
    memblock_list_t *list = block_list;

    while (list){
        num_lists++;
        if (list->min_address == 0x0){
            mem_entry_t *working = list->head;
            if (list->max_address >= (0x0+(256*8))) /* 256*8 is the size of the I-scratchpad in bytes */
                yyerror("Instruction mem() block is larger than instruction scratchpad");
            while (working){
                if ((working->type == ENTRY_IDATA) ||
                    (working->type == ENTRY_FDATA))
                    yyerror("Only instructions are allowed in the instruction mem() block when using -scratchpad");
                working = working->next;
            }
        }
        else if (list->min_address == 0x1000){
            mem_entry_t *working = list->head;
            if (list->max_address >= (0x1000+(256*4))) /* 256*4 is the size of the D-scratchpad in bytes */
                yyerror("Data mem() block is larger than data scratchpad");
            while (working){
                if ((working->type == ENTRY_INSTRUCTION) ||
                    (working->type == ENTRY_PHI_NODE))
                    yyerror("Only data is allowed in the data mem() block when using -scratchpad");
                working = working->next;
            }
        }
        else {
            yyerror("Bad mem() block address when using -scratchpad");
        }
        list = list->next;
    }

    if (num_lists > 2)
        yyerror("Only two mem() blocks are allowed when using -scratchpad");
}

#define SEXT_IMM18(x)    ((int32_t)(((x)&0x20000)?((x)|0xfffc0000):((x)&0x0003ffff)))
#define SEXT_IMM16(x)    ((int32_t)(((x)&0x8000)?((x)|0xffff0000):((x)&0x0000ffff)))

void sprint_asm(char *buff, instruction_t *inst){
    switch (inst->opcode){
        case PISA_J:
            sprintf(buff,"j 0x%x",inst->target_address);
            break;
        case PISA_JAL:
            sprintf(buff,"jal 0x%x",inst->target_address);
            break;
        case PISA_JR:
            sprintf(buff,"jr $r%d",inst->rsrc1);
            break;
        case PISA_JALR:
            sprintf(buff,"jalr $r%d, $r%d",inst->rdst,inst->rsrc1);
            break;
        case PISA_BEQ:
            sprintf(buff,"beq $r%d, $r%d, #%d",inst->rsrc1,inst->rsrc2,SEXT_IMM18(inst->imm));
            break;
        case PISA_BNE:
            sprintf(buff,"bne $r%d, $r%d, #%d",inst->rsrc1,inst->rsrc2,SEXT_IMM18(inst->imm));
            break;
        case PISA_BLEZ:
            sprintf(buff,"blez $r%d, #%d",inst->rsrc1,SEXT_IMM18(inst->imm));
            break;
        case PISA_BGTZ:
            sprintf(buff,"bgtz $r%d, #%d",inst->rsrc1,SEXT_IMM18(inst->imm));
            break;
        case PISA_BLTZ:
            sprintf(buff,"bltz $r%d, #%d",inst->rsrc1,SEXT_IMM18(inst->imm));
            break;
        case PISA_BGEZ:
            sprintf(buff,"bgez $r%d, #%d",inst->rsrc1,SEXT_IMM18(inst->imm));
            break;
        case PISA_BC1F:
            sprintf(buff,"bc1f #%d",SEXT_IMM18(inst->imm));
            break;
        case PISA_BC1T:
            sprintf(buff,"bc1t #%d",SEXT_IMM18(inst->imm));
            break;
        case PISA_LB_D:
            sprintf(buff,"lb $r%d, #%d[$r%d]",inst->rdst,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_LB_I:
            sprintf(buff,"lb $r%d, $r%d[$r%d]",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_LBU_D:
            sprintf(buff,"lbu $r%d, #%d[$r%d]",inst->rdst,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_LBU_I:
            sprintf(buff,"lbu $r%d, $r%d[$r%d]",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_LH_D:
            sprintf(buff,"lh $r%d, #%d[$r%d]",inst->rdst,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_LH_I:
            sprintf(buff,"lh $r%d, $r%d[$r%d]",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_LHU_D:
            sprintf(buff,"lhu $r%d, #%d[$r%d]",inst->rdst,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_LHU_I:
            sprintf(buff,"lhu $r%d, $r%d[$r%d]",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_LW_D:
            sprintf(buff,"lw $r%d, #%d[$r%d]",inst->rdst,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_LW_I:
            sprintf(buff,"lw $r%d, $r%d[$r%d]",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_DLW_D:
            sprintf(buff,"dlw $r%d, #%d[$r%d]",inst->rdst,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_DLW_I:
            sprintf(buff,"dlw $r%d, $r%d[$r%d]",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_L_S_D:
            sprintf(buff,"l.s $r%d, #%d[$r%d]",inst->rdst,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_L_S_I:
            sprintf(buff,"l.s $r%d, $r%d[$r%d]",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_L_D_D:
            sprintf(buff,"l.d $r%d, #%d[$r%d]",inst->rdst,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_L_D_I:
            sprintf(buff,"l.d $r%d, $r%d[$r%d]",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_LWL:
            sprintf(buff,"lwl TODO");
            break;
        case PISA_LWR:
            sprintf(buff,"lwr TODO");
            break;
        case PISA_SB_D:
            sprintf(buff,"sb $r%d, #%d[$r%d]",inst->rsrc0,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_SB_I:
            sprintf(buff,"sb $r%d, $r%d[$r%d]",inst->rsrc0,inst->rsrc2,inst->rsrc1);
            break;
        case PISA_SH_D:
            sprintf(buff,"sh $r%d, #%d[$r%d]",inst->rsrc0,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_SH_I:
            sprintf(buff,"sh $r%d, $r%d[$r%d]",inst->rsrc0,inst->rsrc2,inst->rsrc1);
            break;
        case PISA_SW_D:
            sprintf(buff,"sw $r%d, #%d[$r%d]",inst->rsrc0,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_SW_I:
            sprintf(buff,"sw $r%d, $r%d[$r%d]",inst->rsrc0,inst->rsrc2,inst->rsrc1);
            break;
        case PISA_DSW_D:
            sprintf(buff,"dsw $r%d, #%d[$r%d]",inst->rsrc0,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_DSW_I:
            sprintf(buff,"dsw $r%d, $r%d[$r%d]",inst->rsrc0,inst->rsrc2,inst->rsrc1);
            break;
        case PISA_DSZ_D:
            sprintf(buff,"dsz #%d[$r%d]",SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_DSZ_I:
            sprintf(buff,"dsz $r%d[$r%d]",inst->rsrc2,inst->rsrc1);
            break;
        case PISA_S_S_D:
            sprintf(buff,"s.s $r%d, #%d[$r%d]",inst->rsrc0,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_S_S_I:
            sprintf(buff,"s.s $r%d, $r%d[$r%d]",inst->rsrc0,inst->rsrc2,inst->rsrc1);
            break;
        case PISA_S_D_D:
            sprintf(buff,"s.d $r%d, #%d[$r%d]",inst->rsrc0,SEXT_IMM16(inst->imm),inst->rbase);
            break;
        case PISA_S_D_I:
            sprintf(buff,"s.d $r%d, $r%d[$r%d]",inst->rsrc0,inst->rsrc2,inst->rsrc1);
            break;
        case PISA_SWL:
            sprintf(buff,"swl TODO");
            break;
        case PISA_SWR:
            sprintf(buff,"swr TODO");
            break;
        case PISA_ADD:
            sprintf(buff,"add $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_ADDI:
            sprintf(buff,"addi $r%d, $r%d, 0x%x",inst->rdst,inst->rsrc1,SEXT_IMM16(inst->imm));
            break;
        case PISA_ADDU:
            sprintf(buff,"addu $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_ADDIU:
            sprintf(buff,"addiu $r%d, $r%d, 0x%x",inst->rdst,inst->rsrc1,(inst->imm&0xffff));
            break;
        case PISA_SUB:
            sprintf(buff,"sub $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_SUBU:
            sprintf(buff,"subu $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_MULT:
            sprintf(buff,"mult $r%d, $r%d",inst->rsrc1,inst->rsrc2);
            break;
        case PISA_MULTU:
            sprintf(buff,"multu $r%d, $r%d",inst->rsrc1,inst->rsrc2);
            break;
        case PISA_DIV:
            sprintf(buff,"div $r%d, $r%d",inst->rsrc1,inst->rsrc2);
            break;
        case PISA_DIVU:
            sprintf(buff,"divu $r%d, $r%d",inst->rsrc1,inst->rsrc2);
            break;
        case PISA_MFHI:
            sprintf(buff,"mfhi $r%d",inst->rdst);
            break;
        case PISA_MTHI:
            sprintf(buff,"mthi $r%d",inst->rsrc1);
            break;
        case PISA_MFLO:
            sprintf(buff,"mflo $r%d",inst->rdst);
            break;
        case PISA_MTLO:
            sprintf(buff,"mtlo $r%d",inst->rsrc1);
            break;
        case PISA_AND:
            sprintf(buff,"and $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_ANDI:
            sprintf(buff,"andi $r%d, $r%d, 0x%x",inst->rdst,inst->rsrc1,(inst->imm&0xffff));
            break;
        case PISA_OR:
            sprintf(buff,"or $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_ORI:
            sprintf(buff,"ori $r%d, $r%d, 0x%x",inst->rdst,inst->rsrc1,(inst->imm&0xffff));
            break;
        case PISA_XOR:
            sprintf(buff,"xor $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_XORI:
            sprintf(buff,"xori $r%d, $r%d, 0x%x",inst->rdst,inst->rsrc1,(inst->imm&0xffff));
            break;
        case PISA_NOR:
            sprintf(buff,"nor $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_SLL:
            sprintf(buff,"sll $r%d, $r%d, #%d",inst->rdst,inst->rsrc1,(inst->imm&0x1f));
            break;
        case PISA_SLLV:
            sprintf(buff,"sllv $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_SRL:
            sprintf(buff,"srl $r%d, $r%d, #%d",inst->rdst,inst->rsrc1,(inst->imm&0x1f));
            break;
        case PISA_SRLV:
            sprintf(buff,"srlv $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_SRA:
            sprintf(buff,"sra $r%d, $r%d, #%d",inst->rdst,inst->rsrc1,(inst->imm&0x1f));
            break;
        case PISA_SRAV:
            sprintf(buff,"srav $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_SLT:
            sprintf(buff,"slt $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_SLTI:
            sprintf(buff,"slti $r%d, $r%d, #%d",inst->rdst,inst->rsrc1,SEXT_IMM16(inst->imm));
            break;
        case PISA_SLTU:
            sprintf(buff,"sltu $r%d, $r%d, $r%d",inst->rdst,inst->rsrc1,inst->rsrc2);
            break;
        case PISA_SLTIU:
            sprintf(buff,"sltiu $r%d, $r%d, #%d",inst->rdst,inst->rsrc1,(inst->imm&0xffff));
            break;
        case PISA_ADD_S:
            sprintf(buff,"add.s TODO");
            break;
        case PISA_ADD_D:
            sprintf(buff,"add.d TODO");
            break;
        case PISA_SUB_S:
            sprintf(buff,"sub.s TODO");
            break;
        case PISA_SUB_D:
            sprintf(buff,"sub.d TODO");
            break;
        case PISA_MUL_S:
            sprintf(buff,"mul.s TODO");
            break;
        case PISA_MUL_D:
            sprintf(buff,"mul.d TODO");
            break;
        case PISA_DIV_S:
            sprintf(buff,"div.s TODO");
            break;
        case PISA_DIV_D:
            sprintf(buff,"div.d TODO");
            break;
        case PISA_ABS_S:
            sprintf(buff,"abs.s TODO");
            break;
        case PISA_ABS_D:
            sprintf(buff,"abs.d TODO");
            break;
        case PISA_MOV_S:
            sprintf(buff,"mov.s TODO");
            break;
        case PISA_MOV_D:
            sprintf(buff,"mov.d TODO");
            break;
        case PISA_NEG_S:
            sprintf(buff,"neg.s TODO");
            break;
        case PISA_NEG_D:
            sprintf(buff,"neg.d TODO");
            break;
        case PISA_CVT_S_D:
            sprintf(buff,"cvt.s.d TODO");
            break;
        case PISA_CVT_S_W:
            sprintf(buff,"cvt.s.w TODO");
            break;
        case PISA_CVT_D_S:
            sprintf(buff,"cvt.d.s TODO");
            break;
        case PISA_CVT_D_W:
            sprintf(buff,"cvt.d.w TODO");
            break;
        case PISA_CVT_W_S:
            sprintf(buff,"cvt.w.s TODO");
            break;
        case PISA_CVT_W_D:
            sprintf(buff,"cvt.w.d TODO");
            break;
        case PISA_C_EQ_S:
            sprintf(buff,"c.eq.s TODO");
            break;
        case PISA_C_EQ_D:
            sprintf(buff,"c.eq.d TODO");
            break;
        case PISA_C_LT_S:
            sprintf(buff,"c.lt.s TODO");
            break;
        case PISA_C_LT_D:
            sprintf(buff,"c.lt.d TODO");
            break;
        case PISA_C_LE_S:
            sprintf(buff,"c.le.s TODO");
            break;
        case PISA_C_LE_D:
            sprintf(buff,"c.le.d TODO");
            break;
        case PISA_SQRT_S:
            sprintf(buff,"sqrt.s TODO");
            break;
        case PISA_SQRT_D:
            sprintf(buff,"sqrt.d TODO");
            break;
        case PISA_NOP:
            sprintf(buff,"nop");
            break;
        case PISA_SYSCALL:
            sprintf(buff,"syscall");
            break;
        case PISA_BREAK:
            sprintf(buff,"break");
            break;
        case PISA_LUI:
            sprintf(buff,"lui $r%d, 0x%x",inst->rdst,(inst->imm&0xffff));
            break;
        case PISA_MFC1:
            sprintf(buff,"mfc1 TODO");
            break;
        case PISA_MTC1:
            sprintf(buff,"mtc1 TODO");
            break;
        case PISA_M1T_TRF:
            sprintf(buff,"m1t_trf TODO");
            break;
        case PISA_M2T_TRF:
            sprintf(buff,"m2t_trf TODO");
            break;
        case PISA_MF_TRF:
            sprintf(buff,"mf_trf TODO");
            break;
        case PISA_BARRIER:
            sprintf(buff,"barrier");
            break;
        case PISA_ERET:
            sprintf(buff,"eret");
            break;
        case PISA_MIGRATE:
            sprintf(buff,"migrate");
            break;
        default:
            yyerror("bogus opcode when trying to print instruction asm");
            break;
    }
}

void print_memlist_info(){
    memblock_list_t *list = block_list;

    while (list){
        mem_entry_t *working = list->head;
        printf("\nMem() block: 0x%08x:\n",list->min_address);
        while (working){
            if (working->type == ENTRY_INSTRUCTION){
                char buff[200];
                sprint_asm(buff,working->inst);
                printf("inst:  @0x%08x\t0x%010llx\t%s\n",working->address,working->encoding,buff);
            }
            else if (working->type == ENTRY_IDATA){
                printf("idata: @0x%08x\t0x%x\n",working->address,working->ivalue);
            }
            else if (working->type == ENTRY_FDATA){
                printf("fdata: @0x%08x\t%f\n",working->address,working->fvalue);
            }
            else if (working->type == ENTRY_DEFINITION){
                if (working->name)
                    printf("def: %s skipped\n",working->name);
                else
                    printf("def: <<no name>> skipped\n");
            }
            else if (working->type == ENTRY_PHI_NODE){
                if (working->name)
                    printf("phi: 0x%08x %s skipped\n",working->address,working->name);
                else
                    printf("phi: <<no name>> skipped\n");
            }
            else {
                yyerror("Invalid entry type when emitting instructions");
            }
            working = working->next;
        }
        list = list->next;
    }
}



/* these are cannibalized mem_access functions 
   from 721sim.  This is to support writing a 721sim
   style checkpoint (see below). */
#define SIZE_MEM_TABLE 0x8000
#define SIZE_MEM_BLOCK 0x10000

#define MEM_BLOCK(addr)       ((((uint32_t)(addr)) >> 16) & 0xffff)
#define MEM_OFFSET(addr)      ((addr) & 0xffff)

char **mem_table;

void write_mem(uint32_t addr, void *vp, int nbytes){
    char *p = (char*)vp;

    /* allocate memory blocks if necessary */
    if (!mem_table[MEM_BLOCK(addr)])
        mem_table[MEM_BLOCK(addr)] = (char*)calloc(SIZE_MEM_BLOCK, 1);

    switch (nbytes) {
        case 1:
            *((uint8_t *)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr))) = *((uint8_t *)p);
            break;
        case 2:
            *((uint16_t *)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr))) = *((uint16_t *)p);
            break;
        case 4:
            *((uint32_t *)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr))) = *((uint32_t *)p);
            break;
        case 8:
            *((uint64_t *)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr))) = *((uint64_t *)p);
            break;
        default: {
                /* nbytes >= 16 and power of two */
                uint32_t words = nbytes >> 2;
                while (words-- > 0) {
                    *((uint32_t *)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr))) = *((uint32_t *)p);
                    p += 4;
                    addr += 4;
                }
            }
            break;
    }
}

void read_mem(uint32_t addr, void *vp, int nbytes){
    char *p = (char*)vp;

    /* allocate memory blocks if necessary */
    if (!mem_table[MEM_BLOCK(addr)])
        mem_table[MEM_BLOCK(addr)] = (char*)calloc(SIZE_MEM_BLOCK, 1);

    switch (nbytes) {
        case 1:
            *((uint8_t *)p) = *((uint8_t*)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr)));
            break;
        case 2:
            *((uint16_t *)p) = *((uint16_t*)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr)));
            break;
        case 4:
            *((uint32_t *)p) = *((uint32_t*)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr)));
            break;
        case 8:
            *((uint64_t *)p) = *((uint64_t*)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr)));
            break;
        default: {
                /* nbytes >= 16 and power of two */
                uint32_t words = nbytes >> 2;
                while (words-- > 0) {
                    *((uint32_t *)p) = *((uint32_t*)(mem_table[MEM_BLOCK(addr)]+MEM_OFFSET(addr)));
                    p += 4;
                    addr += 4;
                }
            }
            break;
    }
}


BOOL mem_initted = FALSE;
void fill_mem(char *err){
    int i;
    memblock_list_t *list = NULL;
    if (mem_initted == FALSE){
        mem_table = (char**)malloc(sizeof(char*)*SIZE_MEM_TABLE);
        for (i=0;i<SIZE_MEM_TABLE;i++)
            mem_table[i] = NULL;

        list = block_list;
        while (list){
            mem_entry_t *working = list->head;
            while (working){
                if (working->type == ENTRY_INSTRUCTION){
                    // START DIRTY HACK
                    uint32_t high_word = (uint32_t)((working->encoding >> 32) & 0xffffffff);
                    uint32_t low_word =  (uint32_t)((working->encoding      ) & 0xffffffff);
                    write_mem(working->address,   &(high_word), 4);
                    write_mem(working->address+4, &( low_word), 4);
                    // END DIRTY HACK
                    /* write to mem table */
                    //write_mem(working->address, &(working->encoding), 8);
                }
                else if (working->type == ENTRY_IDATA){
                    /* write to mem table */
                    write_mem(working->address, &(working->ivalue), 4);
                }
                else if (working->type == ENTRY_FDATA){
                    /* write to mem table */
                    write_mem(working->address, &(working->fvalue), 4);
                }
                else if (working->type == ENTRY_DEFINITION){
                    /* do nothing */
                }
                else if (working->type == ENTRY_PHI_NODE){
                    /* do nothing */
                }
                else {
                    yyerror(err);
                }
                working = working->next;
            }
            list = list->next;
        }
        mem_initted = TRUE;
    }
}


/* The following function writes the program to a 721sim 
   checkpoint.  It doesn't actually use the checkpoint 
   code from 721sim because the original checkpoint code
   is not portable from 32 to 64 bit systems.  So, this 
   function looks like non-sense, and it mostly is, but 
   writes a checkpoint that can be read by the rtl testbench */
#define SIZE_CHKPT_HEADER 404
void write_flat(char *file){
    int32_t i;
    unsigned char chkpt_header[SIZE_CHKPT_HEADER];
    uint32_t nblocks = 0;
    FILE *fd = fopen(file,"w");

    for (i=0;i<SIZE_CHKPT_HEADER;i++)
        chkpt_header[i] = 0;

    *((uint32_t*)&chkpt_header[84])=pc;   // PC
    *((uint32_t*)&chkpt_header[88])=pc+8; // NPC

    fwrite(&chkpt_header, 1, SIZE_CHKPT_HEADER, fd); /* write the header */

    /* fill mem table */
    fill_mem("Invalid entry type when writing checkpoint");

    /* track number of touched blocks */
    for (i=0;i<SIZE_MEM_TABLE;i++)
        if (mem_table[i])
            nblocks++;

    /* write number of touched blocks */
    fwrite(&nblocks, 1, sizeof(nblocks), fd);

    /* write blocks */
    for (i=0;i<SIZE_MEM_TABLE;i++){
        if (mem_table[i]){
            // store the row number first
            fwrite(&i, 1, sizeof(i), fd);
            // then store the actual row
            fwrite(mem_table[i],sizeof(char), SIZE_MEM_BLOCK, fd);
        }
    }
    fclose(fd);
}

void write_fpga(char *mfile, char *pfile, char *rfile){
    int i,j;
    FILE *mfd = NULL;
    FILE *pfd = NULL;
    FILE *rfd = NULL;

    fill_mem("Invalid entry type when writing fpga init files");

    mfd = fopen(mfile,"w");
    /* upper 16 bits of addresses */
    for (i=0; i<0x8000; i++){
        if (mem_table[MEM_BLOCK((i<<16))]){
            fprintf(mfd,"%04x\n",i);
            for (j=0; j<0x10000; j+=16){
                uint32_t addr = (i<<16) | j;
                uint32_t word0;
                uint32_t word1;
                uint32_t word2;
                uint32_t word3;
                read_mem((addr+ 0), &word0, 4);
                read_mem((addr+ 4), &word1, 4);
                read_mem((addr+ 8), &word2, 4);
                read_mem((addr+12), &word3, 4);
                //fprintf(mfd,"%08x%08x%08x%08x\n",word2,word3,word0,word1);
                // START DIRTY HACK
                fprintf(mfd,"%08x%08x%08x%08x\n",word3,word2,word1,word0);
                // END DIRTY HACK
            }
        }
    }
    fclose(mfd);

    pfd = fopen(pfile,"w");
    fprintf(pfd,"%08x",pc);
    fclose(pfd);

    rfd = fopen(rfile,"w");
    for (i=0;i<34;i++)
        fprintf(rfd,"00000000000000000000000000000000\n");
    fclose(rfd);
}

void write_scratchpads(char *ifile, char *dfile){
    memblock_list_t *list = block_list;

    while (list){
        if (list->min_address == 0x0){
            mem_entry_t *working = list->head;
            FILE *ifd = fopen(ifile,"w");
            int nentries = 0;
            while (working){
                if ((working->type == ENTRY_INSTRUCTION) ||
                    (working->type == ENTRY_PHI_NODE)){
                    fprintf(ifd,"%010llx\n",working->encoding);
                }
                nentries++;
                working = working->next;
            }
            while (nentries < 256){
                fprintf(ifd,"0000000000\n");
                nentries++;
            }
            fclose(ifd);
        }
        else if (list->min_address == 0x1000){
            mem_entry_t *working = list->head;
            FILE *dfd = fopen(dfile,"w");
            int nentries = 0;
            while (working){
                if ((working->type == ENTRY_IDATA) ||
                    (working->type == ENTRY_FDATA)){
                    fprintf(dfd,"%08x\n",working->ivalue);
                }
                nentries++;
                working = working->next;
            }
            while (nentries < 256){
                fprintf(dfd,"00000000\n");
                nentries++;
            }
            fclose(dfd);
        }
        else {
            yyerror("Bad mem() block address when using -scratchpad");
        }
        list = list->next;
    }
}

symtab_entry_t * symtab_head = NULL;

void symtab_new(char* name, symtab_type_t entry_type){
    int found = 0;
    symtab_entry_t * working = symtab_head;
    while (working){
        if (strcmp(name, working->name) == 0)
            found = 1;
        working = working->next;
    }

    if (found){
        char buff[100];
        sprintf(buff,"Duplicate label declaration: %s.",name);
        yyerror(buff);
    }
    else{
        symtab_entry_t *new_entry = (symtab_entry_t*) malloc(sizeof(symtab_entry_t));
        new_entry->name = strdup(name);
        new_entry->type = entry_type;
        new_entry->next = symtab_head;
        symtab_head = new_entry;
    }
}

void symtab_update(char* name, uint32_t value){
    symtab_entry_t * working = symtab_head;
    symtab_entry_t * entry = NULL;
    while (working){
        if (strcmp(name, working->name) == 0){
            entry = working;
            break;
        }
        working = working->next;
    }

    if (!entry){
        char buff[100];
        sprintf(buff,"Label not declared: %s",name);
        yyerror(buff);
    }
    else{
        entry->value = value;
    }
}

int symtab_lookup(char* name){
    symtab_entry_t * working = symtab_head;
    symtab_entry_t * entry = NULL;
    while (working){
        if (strcmp(name, working->name) == 0){
            entry = working;
            break;
        }
        working = working->next;
    }

    if (!entry){
        return -1;
    }
    else{
        return entry->value;
    }
}

symtab_type_t symtab_type(char* name){
    symtab_entry_t * working = symtab_head;
    symtab_entry_t * entry = NULL;
    while (working){
        if (strcmp(name, working->name) == 0){
            entry = working;
            break;
        }
        working = working->next;
    }

    if (!entry){
        return -1;
    }
    else{
        return entry->type;
    }
}

void dump_symtab(){
    int i = 0;
    symtab_entry_t * working = symtab_head;
    printf("\nSymbol table entries: \n");
    while (working){
        printf("entry[%d]: %s\t%s\t%x\n",i,
                       working->name,
                       (working->type == SYMTAB_MEM)?"mem":"reg",
                       working->value);
        i++;
        working = working->next;
    }
}

void set_pc(uint32_t addr){
    pc = addr;
}

uint64_t encode_instruction(instruction_t *inst){
    uint64_t encoding = 0;
    encoding |= (((uint64_t)inst->opcode)<<32);
    switch (inst->opcode){
        case PISA_J:
            encoding |= ((((uint64_t)inst->target_address)>>2)&0x3ffffff);
            break;
        case PISA_JAL:
            encoding |= ((((uint64_t)inst->target_address)>>2)&0x3ffffff);
            break;
        case PISA_JR:
            encoding |= (inst->rsrc1<<24); /* rs */
            break;
        case PISA_JALR:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            break;
        case PISA_BEQ:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            encoding |= ((inst->imm>>2) & 0xffff); /* imm */
            break;
        case PISA_BNE:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            encoding |= ((inst->imm>>2) & 0xffff); /* imm */
            break;
        case PISA_BLEZ:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= ((inst->imm>>2) & 0xffff); /* imm */
            break;
        case PISA_BGTZ:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= ((inst->imm>>2) & 0xffff); /* imm */
            break;
        case PISA_BLTZ:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= ((inst->imm>>2) & 0xffff); /* imm */
            break;
        case PISA_BGEZ:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= ((inst->imm>>2) & 0xffff); /* imm */
            break;
        case PISA_BC1F:
            encoding |= ((inst->imm>>2) & 0xffff); /* imm */
            break;
        case PISA_BC1T:
            encoding |= ((inst->imm>>2) & 0xffff); /* imm */
            break;
        case PISA_LB_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_LB_I:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_LBU_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_LBU_I:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_LH_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_LH_I:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_LHU_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_LHU_I:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_LW_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_LW_I:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_DLW_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_DLW_I:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_L_S_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rdst<<16);  /* ft */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_L_S_I:
            encoding |= (inst->rdst<<16);  /* ft */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_L_D_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rdst<<16);  /* ft */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_L_D_I:
            encoding |= (inst->rdst<<16);  /* ft */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_LWL: /* TODO */
            break;
        case PISA_LWR: /* TODO */
            break;
        case PISA_SB_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rsrc0<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_SB_I:
            encoding |= (inst->rsrc0<<16); /* ft */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
            break;
        case PISA_SH_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rsrc0<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_SH_I:
            encoding |= (inst->rsrc0<<16); /* ft */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_SW_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rsrc0<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_SW_I:
            encoding |= (inst->rsrc0<<16); /* ft */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_DSW_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rsrc0<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_DSW_I:
            encoding |= (inst->rsrc0<<16); /* ft */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_DSZ_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_DSZ_I:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_S_S_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rsrc0<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_S_S_I:
            encoding |= (inst->rsrc0<<16); /* ft */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_S_D_D:
            encoding |= (inst->rbase<<24); /* rs */
            encoding |= (inst->rsrc0<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_S_D_I:
            encoding |= (inst->rsrc0<<16); /* ft */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<8);  /* rd */
            break;
        case PISA_SWL: /* TODO */
            break;
        case PISA_SWR: /* TODO */
            break;
        case PISA_ADD:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_ADDI:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_ADDU:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_ADDIU:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_SUB:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_SUBU:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_MULT:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_MULTU:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_DIV:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_DIVU:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_MFHI:
            encoding |= (inst->rdst<<8);   /* rd */
            break;
        case PISA_MTHI:
            encoding |= (inst->rsrc1<<24); /* rs */
            break;
        case PISA_MFLO:
            encoding |= (inst->rdst<<8);   /* rd */
            break;
        case PISA_MTLO:
            encoding |= (inst->rsrc1<<24); /* rs */
            break;
        case PISA_AND:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_ANDI:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_OR:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_ORI:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_XOR:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_XORI:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_NOR:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_SLL:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<16); /* rt */
            encoding |= (inst->imm & 0x1f); /* shamt */
            break;
        case PISA_SLLV:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_SRL:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<16); /* rt */
            encoding |= (inst->imm & 0x1f); /* shamt */
            break;
        case PISA_SRLV:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_SRA:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<16); /* rt */
            encoding |= (inst->imm & 0x1f); /* shamt */
            break;
        case PISA_SRAV:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_SLT:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_SLTI:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_SLTU:
            encoding |= (inst->rdst<<8);   /* rd */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc2<<16); /* rt */
            break;
        case PISA_SLTIU:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_ADD_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_ADD_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_SUB_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_SUB_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_MUL_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_MUL_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_DIV_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_DIV_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_ABS_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_ABS_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_MOV_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_MOV_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_NEG_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_NEG_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_CVT_S_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_CVT_S_W:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_CVT_D_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_CVT_D_W:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_CVT_W_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_CVT_W_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_C_EQ_S:
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_C_EQ_D:
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_C_LT_S:
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_C_LT_D:
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_C_LE_S:
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_C_LE_D:
            encoding |= (inst->rsrc1<<24); /* fs */
            encoding |= (inst->rsrc2<<16); /* ft */
            break;
        case PISA_SQRT_S:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_SQRT_D:
            encoding |= (inst->rdst<<8);   /* fd */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_NOP:
            break;
        case PISA_SYSCALL:
            break;
        case PISA_BREAK:
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_LUI:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->imm & 0xffff); /* imm */
            break;
        case PISA_MFC1:
            encoding |= (inst->rdst<<16);  /* rt */
            encoding |= (inst->rsrc1<<24); /* fs */
            break;
        case PISA_MTC1:
            encoding |= (inst->rdst<<24);  /* fs */
            encoding |= (inst->rsrc1<<16); /* rt */
            break;
        case PISA_M1T_TRF:
            encoding |= (inst->rsrc1<<24); /* rs */
            break;
        case PISA_M2T_TRF:
            encoding |= (inst->rsrc1<<24); /* rs */
            encoding |= (inst->rsrc1);     /* ru */
            break;
        case PISA_MF_TRF:
            encoding |= (inst->rdst<<8);   /* rd */
            break;
        case PISA_BARRIER:
            break;
        case PISA_ERET:
            break;
        case PISA_MIGRATE:
            break;
        default:
            yyerror("Encountered an unknown opcode when encoding instructions.");
            break;
    }
    return encoding;
}

