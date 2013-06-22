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
                    else if (working->inst->opcode == PISA_ADDI){
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

void print_instructions(){
    memblock_list_t *list = block_list;

    while (list){
        mem_entry_t *working = list->head;
        printf("\nMem() block: 0x%08x:\n",list->min_address);
        while (working){
            if (working->type == ENTRY_INSTRUCTION){
                printf("inst:  @0x%08x\t0x%010llx\n",working->address,working->encoding);
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



/* these is a cannibalized mem_access function 
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
    memblock_list_t *list = NULL;
    FILE *fd = fopen(file,"w");
    mem_table = (char**)malloc(sizeof(char*)*SIZE_MEM_TABLE);

    for (i=0;i<SIZE_CHKPT_HEADER;i++)
        chkpt_header[i] = 0;

    *((uint32_t*)&chkpt_header[84])=pc;   // PC
    *((uint32_t*)&chkpt_header[88])=pc+8; // NPC

    fwrite(&chkpt_header, 1, SIZE_CHKPT_HEADER, fd); /* write the header */

    for (i=0;i<SIZE_MEM_TABLE;i++)
        mem_table[i] = NULL;

    /* TODO fill mem table */
    list = block_list;
    while (list){
        mem_entry_t *working = list->head;
        while (working){
            if (working->type == ENTRY_INSTRUCTION){
                /* write to mem table */
                write_mem(working->address, &(working->encoding), 8);
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
                yyerror("Invalid entry type when writing checkpoint");
            }
            working = working->next;
        }
        list = list->next;
    }

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

