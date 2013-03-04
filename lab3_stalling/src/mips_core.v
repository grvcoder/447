/*
 *
 * Redistributions of any form whatsoever must retain and/or include the
 * following acknowledgment, notices and disclaimer:
 *
 * This product includes software developed by Carnegie Mellon University. 
 *
 * Copyright (c) 2004 by Babak Falsafi and James Hoe,
 * Computer Architecture Lab at Carnegie Mellon (CALCM), 
 * Carnegie Mellon University.
 *
 * This source file was written and maintained by Jared Smolens 
 * as part of the Two-Way In-Order Superscalar project for Carnegie Mellon's 
 * Introduction to Computer Architecture course, 18-447. The source file
 * is in part derived from code originally written by Herman Schmit and 
 * Diana Marculescu.
 *
 * You may not use the name "Carnegie Mellon University" or derivations 
 * thereof to endorse or promote products derived from this software.
 *
 * If you modify the software you must place a notice on or within any 
 * modified version provided or made available to any third party stating 
 * that you have modified the software.  The notice shall include at least 
 * your name, address, phone number, email address and the date and purpose 
 * of the modification.
 *
 * THE SOFTWARE IS PROVIDED "AS-IS" WITHOUT ANY WARRANTY OF ANY KIND, EITHER 
 * EXPRESS, IMPLIED OR STATUTORY, INCLUDING BUT NOT LIMITED TO ANYWARRANTY 
 * THAT THE SOFTWARE WILL CONFORM TO SPECIFICATIONS OR BE ERROR-FREE AND ANY 
 * IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, 
 * TITLE, OR NON-INFRINGEMENT.  IN NO EVENT SHALL CARNEGIE MELLON UNIVERSITY 
 * BE LIABLE FOR ANY DAMAGES, INCLUDING BUT NOT LIMITED TO DIRECT, INDIRECT, 
 * SPECIAL OR CONSEQUENTIAL DAMAGES, ARISING OUT OF, RESULTING FROM, OR IN 
 * ANY WAY CONNECTED WITH THIS SOFTWARE (WHETHER OR NOT BASED UPON WARRANTY, 
 * CONTRACT, TORT OR OTHERWISE).
 *
 */

//////
////// MIPS 447: A single-cycle MIPS ISA simulator
//////

// Include the MIPS constants
`include "mips_defines.vh"
`include "internal_defines.vh"

////
//// The MIPS standalone processor module
////
////   clk          (input)  - The clock
////   inst_addr    (output) - Address of instruction to load
////   inst         (input)  - Instruction from memory
////   inst_excpt   (input)  - inst_addr not valid
////   mem_addr     (output) - Address of data to load
////   mem_data_in  (output) - Data for memory store
////   mem_data_out (input)  - Data from memory load
////   mem_write_en (output) - Memory write mask
////   mem_excpt    (input)  - mem_addr not valid
////   halted       (output) - Processor halted
////   reset        (input)  - Reset the processor
////   

module mips_core(/*AUTOARG*/
   // Outputs
   inst_addr, mem_addr, mem_data_in, mem_write_en, halted,
   // Inputs
   clk, inst_excpt, mem_excpt, inst, mem_data_out, rst_b
   );
   
   parameter text_start  = 32'h00400000; /* Initial value of $pc */

   // Core Interface
   input         clk, inst_excpt, mem_excpt;
   output [29:0] inst_addr;
   output [29:0] mem_addr;
   input  [31:0] inst, mem_data_out;
   output [31:0] mem_data_in;
   output [3:0]  mem_write_en;
   output        halted;
   input         rst_b;

   // Internal signals
   wire [31:0]   pc, nextpc, nextnextpc;
   wire          exception_halt, syscall_halt, internal_halt;
   wire          load_epc, load_bva, load_bva_sel;
   wire [31:0]   rt_data, rs_data, rd_data, alu__out, r_v0;
   wire [31:0]   epc, cause, bad_v_addr;
   wire [4:0]    cause_code;
   wire          stall; 

   // Decode signals
   wire [31:0]   dcd_se_imm, dcd_se_offset, dcd_e_imm, dcd_se_mem_offset;
   wire [5:0]    dcd_op, dcd_funct2;
   wire [4:0]    dcd_rs, dcd_funct1, dcd_rt, dcd_rd, dcd_shamt;
   wire [15:0]   dcd_offset, dcd_imm;
   wire [25:0]   dcd_target;
   wire [19:0]   dcd_code;
   wire          dcd_bczft;
   wire [4:0]    rd_num,rs_num;
   wire [31:0]   shiftVal;	
    
   // Execute signals
   wire [31:0] alu__op2,immVal, mult__data;
   wire [2:0]  mult_op;
   
   // Memory signals
   wire [31:0]   ld_mem_data, memData;
   
   // Writeback signals
   wire [4:0] sa;
   wire [31:0] shift_data;
   
   // Pipeline signals
   wire [31:0]   dcd_inst; 
   wire          ex_ctrl_we,mem_ctrl_we,wb_ctrl_we;
   wire          ex_ctrl_Sys;
   wire          mem_syscall_halt,wb_syscall_halt;
   wire          ex_isImm,mem_isImm,wb_isImm;
   wire          ex_isShift,mem_isShift,wb_isShift;
   wire          ex_leftShift,mem_leftShift,wb_leftShift;
   wire          ex_arithShift,mem_arithShift,wb_arithShift;
   wire          ex_en_memLd,mem_en_memLd;
   wire          ex_memToReg,mem_memToReg,wb_memToReg;
   wire          ex_isLui,mem_isLui,wb_isLui;
   wire          ex_isSe;
   wire [2:0]    ex_ldType, mem_ldType;
   wire [3:0]    ex_alu__sel;
   wire [31:0]   ex_rs_data, mem_rs_data,wb_rs_data;
   wire [31:0]   ex_rt_data, mem_rt_data,wb_rt_data;
   wire [31:0]   ex_shiftVal, mem_shiftVal,wb_shiftVal;
   wire [31:0]   ex_e_imm;
   wire [31:0]   ex_se_imm;
   wire [4:0]    ex_shamt,mem_shamt,wb_shamt;
   wire [31:0]   mem_alu__out,wb_alu__out;
   wire [4:0]    ex_rd_num,mem_rd_num,wb_rd_num;
   wire [31:0]   wb_ld_mem_data;
   wire [31:0]   wb_memData;
   wire [2:0]    ex_mult_op;
   wire          ex_mult_act;
   wire [31:0]   mem_mult__data, wb_mult__data;

   // Fetch/*{{{*/
   
   // PC Management
   register #(32, text_start) PCReg(pc, nextpc, clk, ~stall,
                                       1'b0, rst_b);
   register #(32, text_start+4) PCReg2(nextpc, nextnextpc, clk,
                                       ~stall,1'b0, rst_b);
   add_const #(4) NextPCAdder(nextnextpc, nextpc);
   assign        inst_addr = pc[31:2];
   /*}}}*/

   //FETCH-DECODE PIPLELINE REGISTERS/*{{{*/
   register #(32, 32'h14000000) FT_ID_Reg0(dcd_inst,inst,clk, ~stall, 1'b0, rst_b); /*}}}*/

   // Instruction decoding/*{{{*/
   assign        dcd_op = dcd_inst[31:26];    // Opcode
   assign        dcd_rs = dcd_inst[25:21];    // rs field
   assign        dcd_rt = dcd_inst[20:16];    // rt field
   assign        dcd_rd = dcd_inst[15:11];    // rd field
   assign        dcd_shamt = dcd_inst[10:6];  // Shift amount
   assign        dcd_bczft = dcd_inst[16];    // bczt or bczf?
   assign        dcd_funct1 = dcd_inst[4:0];  // Coprocessor 0 function field
   assign        dcd_funct2 = dcd_inst[5:0];  // funct field; secondary opcode
   assign        dcd_offset = dcd_inst[15:0]; // offset field
        // Sign-extended offset for branches
   assign        dcd_se_offset = { {14{dcd_offset[15]}}, dcd_offset, 2'b00 };
        // Sign-extended offset for load/store
   assign        dcd_se_mem_offset = { {16{dcd_offset[15]}}, dcd_offset };
   assign        dcd_imm = dcd_inst[15:0];        // immediate field
   assign        dcd_e_imm = { 16'h0, dcd_imm };  // zero-extended immediate
        // Sign-extended immediate
   assign        dcd_se_imm = { {16{dcd_imm[15]}}, dcd_imm };
   assign        dcd_target = dcd_inst[25:0];     // target field
   assign        dcd_code = dcd_inst[25:6];       // Breakpoint code

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [3:0]	alu__sel;		// From Decoder of mips_decode.v
   wire			arithShift;		// From Decoder of mips_decode.v
   wire			ctrl_RI;		// From Decoder of mips_decode.v
   wire			ctrl_Sys;		// From Decoder of mips_decode.v
   wire			ctrl_we;		// From Decoder of mips_decode.v
   wire			isImm;			// From Decoder of mips_decode.v
   wire			isLui;			// From Decoder of mips_decode.v
   wire			isSe;			// From Decoder of mips_decode.v
   wire			isShift;		// From Decoder of mips_decode.v
   wire [2:0]	ldType;			// From Decoder of mips_decode.v
   wire			leftShift;		// From Decoder of mips_decode.v
   wire			memToReg;		// From Decoder of mips_decode.v
   wire			en_memLd;		// From Decoder of mips_decode.v
   wire	[1:0] 	regDest;    	// From Decoder of mips_decode.v
   wire         mult_act;   	// From Decoder of mips_decode.v
   wire [2:0]   mult_go;    	// From Decoder of mips_decode.v
   // End of automatics
	
   // Generate control signals
   mips_decode Decoder(/*AUTOINST*/
		       // Outputs
		       .ctrl_we		(ctrl_we),
		       .ctrl_Sys	(ctrl_Sys),
		       .ctrl_RI		(ctrl_RI),
		       .regDest		(regDest),
		       .isImm		(isImm),
		       .isShift		(isShift),
		       .leftShift	(leftShift),
		       .arithShift	(arithShift),
		       .en_memLd	(en_memLd),
		       .memToReg	(memToReg),
		       .isLui		(isLui),
		       .isSe		(isSe),
		       .ldType		(ldType[2:0]),
		       .alu__sel	(alu__sel[3:0]),
		       .mult_act    (mult_act),
               .mult_op     (mult_op),
               // Inputs
		       .dcd_op		(dcd_op[5:0]),
		       .dcd_funct2	(dcd_funct2[5:0]),
		       .dcd_rd	    (dcd_rd),
		       .dcd_rt	    (dcd_rt));
   
   mux4_1 #(5)  writeReg(rd_num,dcd_rd,dcd_rt,5'd31,5'd31,regDest);
   mux4_1 #(32) writeData(rd_data,wb_alu__out, wb_ld_mem_data,shiftVal,
                            wb_mult__data,{wb_isShift,wb_memToReg});
   mux2_1 #(5) syscallMux(rs_num,5'd2,dcd_rs,ctrl_Sys);

 /*}}}*/

   //DECODE-EXECUTE PIPLELINE REGISERS/*{{{*/
   register #(1, 0) ID_EX_Reg0(ex_ctrl_we,ctrl_we,clk, ~internal_halt, stall, rst_b);
   register #(1, 0) ID_EX_Reg1(ex_ctrl_Sys,ctrl_Sys,clk, ~internal_halt, stall, rst_b);
   register #(1, 1'bx) ID_EX_Reg2(ex_isImm,isImm,clk, ~internal_halt, stall, rst_b);
   register #(1, 0) ID_EX_Reg3(ex_isShift,isShift,clk, ~internal_halt, stall, rst_b);
   register #(1, 1'bx) ID_EX_Reg4(ex_leftShift,leftShift,clk, ~internal_halt,  stall, rst_b);
   register #(1, 1'bx) ID_EX_Reg5(ex_arithShift,arithShift,clk, ~internal_halt, stall, rst_b);
   register #(1, 1'bx) ID_EX_Reg6(ex_en_memLd,en_memLd,clk, ~internal_halt, stall, rst_b);
   register #(1, 0) ID_EX_Reg7(ex_memToReg,memToReg,clk, ~internal_halt, stall, rst_b);
   register #(1, 0) ID_EX_Reg8(ex_isLui,isLui,clk, ~internal_halt, stall, rst_b);
   register #(1, 1'bx) ID_EX_Reg9(ex_isSe,isSe,clk, ~internal_halt, stall, rst_b);
   register #(3, 3'hx) ID_EX_Reg10(ex_ldType,ldType,clk, ~internal_halt, stall, rst_b);
   register #(4, 4'hx) ID_EX_Reg11(ex_alu__sel,alu__sel,clk, ~internal_halt, stall, rst_b);
   register #(32, 0) ID_EX_Reg12(ex_rs_data,rs_data,clk, ~internal_halt, stall, rst_b);
   register #(32, 0) ID_EX_Reg13(ex_rt_data,rt_data,clk, ~internal_halt, stall, rst_b);
   register #(32, 0) ID_EX_Reg14(ex_e_imm,dcd_e_imm,clk, ~internal_halt, stall, rst_b);
   register #(32, 0) ID_EX_Reg15(ex_se_imm,dcd_se_imm,clk, ~internal_halt, stall,rst_b);
   register #(5, 0) ID_EX_Reg16(ex_shamt,dcd_shamt,clk, ~internal_halt, stall, rst_b);
   register #(5, 0) ID_EX_Reg17(ex_rd_num,rd_num,clk, ~internal_halt, stall, rst_b); 
   register #(1, 0) ID_EX_Reg18(ex_mult_act,mult_act,clk, ~internal_halt, stall, rst_b); 
   register #(3, 0) ID_EX_Reg19(ex_mult_op,mult_op,clk, ~internal_halt, stall, rst_b); 
/*}}}*/

   // Execute/*{{{*/

   mips_ALU ALU(.alu__out(alu__out), 
                .alu__op1(ex_rs_data),
                .alu__op2(alu__op2),
                .alu__sel(ex_alu__sel));
 
   mux2_1 #(32) aluOpr2(alu__op2, immVal, ex_rt_data, ex_isImm);
   mux2_1 #(32) se_e_mux(immVal, ex_se_imm, ex_e_imm, ex_isSe);
  
  multiply_coprocessor mult(
                //Output
                .mul__rd_data   (mult__data),
                //Inputs
                .clk            (clk), 
                .rst_b          (rst_b),
                .mul__opcode    (ex_mult_op),  
                .mul__active    (ex_mult_act), 
                .rt_data        (ex_rt_data),
                .rs_data        (ex_rs_data));

   //Syscall Handling
   syscall_unit SU(.syscall_halt(syscall_halt), .pc(pc), .clk(clk), 
                        .Sys(ex_ctrl_Sys), .r_v0(ex_rs_data), .rst_b(rst_b));
   /*}}}*/

   //EXECUTE-MEMORY PIPLELINE REGISTERS/*{{{*/
   register #(1, 0) EX_MEM_Reg0(mem_ctrl_we,ex_ctrl_we,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0)EX_MEM_Reg1(mem_alu__out,alu__out,clk, ~internal_halt, 1'b0, rst_b); 
   register #(32, 0)EX_MEM_Reg2(mem_mult__data,mult__data,clk, ~internal_halt, 1'b0, rst_b); 
   register #(3, 3'hx) EX_MEM_Reg3(mem_ldType,ex_ldType,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0)EX_MEM_Reg4(mem_rt_data,ex_rt_data,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 1'bx) EX_MEM_Reg5(mem_en_memLd,ex_en_memLd,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 0) EX_MEM_Reg6(mem_memToReg,ex_memToReg,clk, ~internal_halt, 1'b0, rst_b);
   register #(5, 0) EX_MEM_Reg7(mem_rd_num,ex_rd_num,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0)EX_MEM_Reg8(mem_rs_data,ex_rs_data,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 0) EX_MEM_Reg9(mem_isShift,ex_isShift,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 0) EX_MEM_Reg10(mem_isLui,ex_isLui,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 1'bx) EX_MEM_Reg11(mem_isImm,ex_isImm,clk, ~internal_halt, 1'b0, rst_b);
   register #(5, 0) EX_MEM_Reg12(mem_shamt,ex_shamt,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 1'bx) EX_MEM_Reg13(mem_leftShift,ex_leftShift,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 1'bx) EX_MEM_Reg14(mem_arithShift,ex_arithShift,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0) EX_MEM_Reg15(mem_shiftVal,shiftVal,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 0) EX_MEM_Reg16(mem_syscall_halt,syscall_halt,clk, ~internal_halt, 1'b0, rst_b);
/*}}}*/

   //Memory Module/*{{{*/

   assign        mem_addr = mem_alu__out[31:2];

   memLoader 	 ldToMem(mem_data_in, mem_write_en, mem_rt_data, mem_alu__out[1:0],
   							mem_ldType, mem_en_memLd);
   memdecoder 	sel_mem(ld_mem_data, memData,mem_alu__out[1:0],mem_ldType);
   mux2_1 #(32) memMux(memData,mem_data_out,mem_alu__out,mem_memToReg);
   /*}}}*/

   //MEMORY-WRITE BACK PIPLELINE REGISTERS/*{{{*/
   register #(5, 0) MEM_WB_Reg0(wb_rd_num,mem_rd_num,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0) MEM_WB_Reg1(wb_alu__out,mem_alu__out,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0) MEM_WB_Reg2(wb_mult__data,mem_mult__data,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0) MEM_WB_Reg3(wb_ld_mem_data,ld_mem_data,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 0) MEM_WB_Reg4(wb_ctrl_we,mem_ctrl_we,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 0) MEM_WB_Reg5(wb_isShift,mem_isShift,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 0) MEM_WB_Reg6(wb_memToReg,mem_memToReg,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 0) MEM_WB_Reg7(wb_isLui,mem_isLui,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 1'bx) MEM_WB_Reg8(wb_isImm,mem_isImm,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0) MEM_WB_Reg9(wb_memData,memData,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0) MEM_WB_Reg10(wb_rt_data,mem_rt_data,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0) MEM_WB_Reg11(wb_rs_data,mem_rs_data,clk, ~internal_halt, 1'b0, rst_b);
   register #(5, 0) MEM_WB_Reg12(wb_shamt,mem_shamt,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 1'bx) MEM_WB_Reg13(wb_leftShift,mem_leftShift,clk, ~internal_halt, 1'b0, rst_b); 
   register #(1, 1'bx) MEM_WB_Reg14(wb_arithShift,mem_arithShift,clk, ~internal_halt, 1'b0, rst_b);
   register #(1, 0) MEM_WB_Reg15(wb_syscall_halt,mem_syscall_halt,clk, ~internal_halt, 1'b0, rst_b);
   register #(32, 0) MEM_WB_Reg16(wb_shiftVal,mem_shiftVal,clk, ~internal_halt, 1'b0, rst_b);
/*}}}*/

   //Write Back/*{{{*/

   // Register File  

   regfile file(// Outputs
   			.rs_data	(rs_data), 
			.rt_data	(rt_data),
   			// Inputs
   			.rs_num		(rs_num), 
			.rt_num		(dcd_rt), 
			.rd_num		(wb_rd_num), 
			.rd_data	(rd_data), 
			.rd_we		(wb_ctrl_we), 
			.clk		(clk), 
			.rst_b		(rst_b), 
			.halted		(halted));

   mux2_1 #(32) shiftMux(shift_data, wb_memData, wb_rt_data, wb_isLui);
   mux4_1 #(5)  shiftBy(sa,wb_rs_data[4:0],wb_shamt,5'd16,5'd16,
                                                    {wb_isLui,wb_isImm});
   shift_reg sr(shiftVal, shift_data, sa, wb_leftShift, wb_arithShift);
/*}}}*/

   //Depencency Detection
   stall_unit dependU(.stall   (stall), 
                 .dcd_rs       (dcd_rs),
                 .dcd_rt       (dcd_rt),
                 .dest         (rd_num),
                 .pip_dest     (wb_rd_num),
                 .willWrite    (~stall & ctrl_we),
                 .wroteBack    (wb_ctrl_we),
                 .ctrl_Sys     (ctrl_Sys),
                 .clk          (clk),
                 .rst_b        (rst_b));

   // Miscellaneous stuff (Exceptions, syscalls, and halt)
   exception_unit EU(.exception_halt(exception_halt), .pc(pc), .rst_b(rst_b),
                     .clk(clk), .load_ex_regs(load_ex_regs),
                     .load_bva(load_bva), .load_bva_sel(load_bva_sel),
                     .cause(cause_code),
                     .IBE(inst_excpt),
                     .DBE(1'b0),
                     .RI(ctrl_RI),
                     .Ov(1'b0),
                     .BP(1'b0),
                     .AdEL_inst(pc[1:0]?1'b1:1'b0),
                     .AdEL_data(1'b0),
                     .AdES(1'b0),
                     .CpU(1'b0));

   assign        internal_halt = exception_halt | wb_syscall_halt;
   register #(1, 0) Halt(halted, internal_halt, clk, 1'b1, 1'b0, rst_b);
   register #(32, 0) EPCReg(epc, pc, clk, load_ex_regs, 1'b0, rst_b);
   register #(32, 0) CauseReg(cause,
                              {25'b0, cause_code, 2'b0}, 
                              clk, load_ex_regs, 1'b0, rst_b);
   register #(32, 0) BadVAddrReg(bad_v_addr, pc, clk, load_bva, 1'b0, rst_b);

endmodule // mips_core

//OTHER MODULES/*{{{*/

////
//// mips_ALU: Performs all arithmetic and logical operations
////
//// out (output) - Final result
//// in1 (input)  - Operand modified by the operation
//// in2 (input)  - Operand used (in arithmetic ops) to modify in1
//// sel (input)  - Selects which operation is to be performed
////
module mips_ALU(alu__out, alu__op1, alu__op2, alu__sel);

   output [31:0] alu__out;
   reg [31:0] alu__out;
   input [31:0]  alu__op1, alu__op2;
   input [3:0]   alu__sel;
   
   always @ * begin
   	case (alu__sel)
		`ALU_ADD:   alu__out = alu__op1 + alu__op2;
		`ALU_SUB:   alu__out = alu__op1 - alu__op2;
		`ALU_AND:   alu__out = alu__op1 & alu__op2;
		`ALU_OR:    alu__out = alu__op1 | alu__op2;
        `ALU_NOR:   alu__out = ~(alu__op1 | alu__op2);
		`ALU_XOR:   alu__out = alu__op1 ^ alu__op2;
		`ALU_SLT:   alu__out = ($signed(alu__op1) < $signed(alu__op2));
		`ALU_SLTU:  alu__out = ($unsigned(alu__op1) < $unsigned(alu__op2));
		`ALU_BEQ:   alu__out = (alu__op1 == alu__op2);
		`ALU_BNE:   alu__out = (alu__op1 != alu__op2);
		`ALU_BLE:   alu__out = (alu__op1[31] == 1 || alu__op1==0);
		`ALU_BGE:   alu__out = (alu__op1[31] == 0 || alu__op1==0);
		`ALU_BL:   	alu__out = (alu__op1[31] == 1);
		`ALU_BG:   	alu__out = (alu__op1[31] == 0 && alu__op1 !=0);
		default:  alu__out = alu__out;
	endcase 
   end

endmodule


//// register: A register which may be reset to an arbirary value
////
//// q      (output) - Current value of register
//// d      (input)  - Next value of register
//// clk    (input)  - Clock (positive edge-sensitive)
//// enable (input)  - Load new value?
//// reset  (input)  - System reset
////
module register(q, d, clk, enable,stallToZero, rst_b);

   parameter
            width = 32,
            reset_value = 0;

   output [(width-1):0] q;
   reg [(width-1):0]    q;
   input [(width-1):0]  d;
   input                 clk, enable, stallToZero, rst_b;

   always @(posedge clk or negedge rst_b)
     if (~rst_b)
       q <= reset_value;
     else if (stallToZero)
        q <= reset_value;
     else if (enable)
       q <= d;
     else
       q <= q;

endmodule // register


//// shift register: A register which shifts it input sa times
////
//// q      (output) - Current value of register
//// d      (input)  - Next value of register
//// clk    (input)  - Clock (positive edge-sensitive)
//// enable (input)  - Load new value
//// reset  (input)  - System reset
////
module shift_reg(q, d, sa, left, arith);

   output [31:0] q;
   input [31:0]  d;
   input [4:0] 	 sa;
   input         left, arith;
   
   reg [31:0]    q;

   always @ (*) begin
     if (left)
       q = d<<sa;
	 else if (arith)
	   q = $signed(d)>>>sa;
	 else
	   q = d>>sa;
   end
endmodule // shift_reg


////
//// adder
////
//// out (output) - adder result
//// in1 (input)  - Operand1
//// in2 (input)  - Operand2
//// sub (input)  - Subtract?
////
module adder(out, in1, in2, sub);
   output [31:0] out;
   input [31:0]  in1, in2;
   input         sub;

   assign        out = sub?(in1 - in2):(in1 + in2);

endmodule // adder


////
//// 2:1 mux
////
//// out (output) - selected mux value
//// in1 (input)  - Value1
//// in2 (input)  - Value2
//// sel (input)  - select line
////
module mux2_1 (out, in1, in2, sel);
	
	parameter 
			width = 32;

	output [width-1:0] out;
	input [width-1:0]  in1, in2;
	input 		  sel;

	assign 		  out = sel ? in1 : in2;

endmodule // mux2_1

////
//// 4:1 mux
////
//// out (output) - selected mux value
//// in1 (input)  - Value1
//// in2 (input)  - Value2
//// in3 (input)  - Value3
//// in4 (input)  - Value4
//// sel (input)  - select line
////
module mux4_1 (out, in1, in2, in3, in4, sel);
	
	parameter 
			width = 32;

	output [width-1:0] out;
	reg [width-1:0] out;
	input [width-1:0]  in1, in2, in3, in4;
	input [1:0]		   sel;

	always @ * begin
		if(sel==2'b0)
			out = in1;
		else if(sel==2'b1)
			out = in2;
		else if(sel==2'b10)
			out = in3;
		else
			out = in4;
	end
endmodule // mux4_1

////
//// add_const: An adder that adds a fixed constant value
////
//// out (output) - adder result
//// in  (input)  - Operand
////
module add_const(out, in);

   parameter add_value = 1;

   output   [31:0] out;
   input    [31:0] in;

   assign   out = in + add_value;

endmodule // adder

////
//// Memory Data Selector 
////
//// out (output) - selected mux value
//// in1 (input)  - Value1
//// in2 (input)  - Value2
//// in3 (input)  - Value3
//// sel (input)  - select line
////
module memdecoder (memOut, memIn, sel, ldType);
	
	output [31:0] 	   memOut;
	reg [31:0]	 	   memOut;
	input [31:0]  	   memIn;
	input [1:0]		   sel;
	input [2:0]		   ldType;

	always @ * begin
		if(ldType == `MEM_U_BYTE) begin
			if (sel == 2'd0) 	memOut = {24'b0,memIn[7:0]};
			else if (sel==2'd1) memOut = {24'b0,memIn[15:8]};
			else if (sel==2'd2)	memOut = {24'b0,memIn[23:16]};
			else if (sel==2'd3)	memOut = {24'b0,memIn[31:24]};
			else				memOut = 32'hx;
		end
		else if(ldType == `MEM_BYTE) begin
			if (sel == 2'd0) 	memOut = {{24{memIn[7]}},memIn[7:0]};
			else if (sel==2'd1) memOut = {{24{memIn[15]}},memIn[15:8]};
			else if (sel==2'd2)	memOut = {{24{memIn[23]}},memIn[23:16]};
			else if (sel==2'd3)	memOut = {{24{memIn[31]}},memIn[31:24]};
			else				memOut = 32'hx;
		end
		else if(ldType == `MEM_U_HALF) begin
			if (sel > 2'd1)		memOut =  {16'b0,memIn[31:16]};
			else if (sel <2'd2)	memOut =  {16'b0,memIn[15:0]};
			else				memOut = 32'hx;
		end
		else if(ldType == `MEM_HALF) begin
			if (sel > 2'd1)		memOut =  {{24{memIn[31]}},memIn[31:16]};
			else if (sel <2'd2)	memOut =  {{24{memIn[15]}},memIn[15:0]};
			else				memOut = 32'hx;
		end
		else if(ldType == `MEM_WORD) begin
			memOut = memIn;
		end
		else
			memOut = 32'hx;
	end
endmodule // memdecoder

module memLoader (dataOut,mem_we, dataIn, sel,ldType, enable);
	
	output [31:0] 	dataOut;
	output [3:0] 	mem_we;
	reg [31:0] 		dataOut;
	reg [3:0] 		mem_we;
	input [31:0] 	dataIn;
	input [1:0] 	sel;
	input [2:0] 	ldType;
	input		  	enable;

	always @ * begin
		if (enable) begin
			if(ldType == `MEM_BYTE) begin
				if (sel == 2'd0) begin
					dataOut = {24'd0,dataIn[7:0]};
					mem_we = 4'b1000;
				end
				else if (sel==2'd1) begin
					dataOut = {16'd0,dataIn[7:0],8'd0};
					mem_we = 4'b0100;
				end
				else if (sel==2'd2) begin
					dataOut = {8'd0,dataIn[7:0],16'd0};
					mem_we = 4'b0010;
				end
				else if (sel==2'd3) begin
					dataOut = {dataIn[7:0],24'd0};
					mem_we = 4'b0001;
				end
				else begin	
					dataOut = 32'hx;
					mem_we = 4'b0;
				end
			end
			else if(ldType == `MEM_HALF) begin
				if (sel > 2'd1) begin
					dataOut = {dataIn[15:0],16'd0};
					mem_we = 4'b0011;
				end
				else if (sel <2'd2) begin
					dataOut = {16'd0,dataIn[15:0]};
					mem_we = 4'b1100;
				end
				else begin
					dataOut = 32'hx;
				end
			end
			else if(ldType == `MEM_WORD) begin
				dataOut = dataIn;
				mem_we = 4'hF;
			end
			else begin
				dataOut = 32'hx;
				mem_we = 4'b0;
			end
		end
		else begin
			dataOut = 32'hx;
			mem_we = 4'b0;
		end
	end
endmodule
/*}}}*/

module stall_unit(stall, dcd_rs,dcd_rt,
                    dest,pip_dest,
                    willWrite,wroteBack,
                    ctrl_Sys,clk, rst_b);
    
    output            stall;
    input      [4:0]  dcd_rs, dcd_rt, dest, pip_dest;
    input             willWrite, wroteBack,
                        ctrl_Sys, clk, rst_b;

    reg [31:0] valid;

    assign stall = (~valid[dcd_rs]) || (~valid[dcd_rt]) || (ctrl_Sys&~valid[2]);
    
    always @ (posedge clk or negedge rst_b) begin
        if(~rst_b) 
            valid <= 32'hffffffff;
        else if (wroteBack)
            valid[pip_dest] <= 1;
        else if (willWrite)
            valid[dest] <=0;


    end
endmodule

// Local Variables:
// verilog-library-directories:("." "../446rtl")
// End:
