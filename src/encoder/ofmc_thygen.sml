(*****************************************************************************
 * Isabelle-OFMC --- Connecting OFMC and Isabelle/HOL
 *                                                                            
 * ofmc_thygen.sml --- 
 * This file is part of Isabelle-OFMC.
 *
 * Copyright (c) 2009 Achim D. Brucker, Germany
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 ******************************************************************************)

signature OFMC_ENCODER = 
sig
  type result
  val ofmc_thygen:          OfmcFp.ofmc_fp -> result * OfmcFp.ofmc_fp
  val ofmc_thygenAnB:       string -> result * OfmcFp.ofmc_fp
  val main:                 string * string list -> unit * OfmcFp.ofmc_fp			     
end

structure ofmc_thygen = 
struct
datatype result = unknownError | success | parseError | attackOfmc | attackIsabelle

fun string_of_result unknownError    = "unkown error"
  | string_of_result success         = "success"
  | string_of_result parseError      = "parse error"
  | string_of_result attackOfmc      = "attack found by ofmc"
  | string_of_result attackIsabelle  = "attack found by isabelle"


val varcnt = ref ~1
val noproof = ref false
val version = "0.1"

fun varcount () = ((varcnt := !varcnt + 1); Int.toString(!varcnt))
fun reset_varcount () = ((varcnt := ~1);())


open ofmc_abstraction


fun gen_header ofmcfp = 
    let
      val protocol = protocol_of ofmcfp
      fun filename f =  let 
	val filename = (hd o List.rev o (String.tokens (fn c => ( c = #"/") orelse (c = #"\\")))) f
      in 
	if (String.isSubstring ".AnB" filename)
	then String.substring(filename,0,(String.size filename) -4)
	else filename
      end
    in
       "chapter {* Analysing "^(protocol)^" *}\n"
      ^"(* *********************************** \n"
      ^"   This file is automatically generated from the AnB file \""
      ^(source_of ofmcfp)^"\".\n"
      ^"   Backend: "^(backend_of ofmcfp)^"\n"
      ^"************************************ *)\n\n"
      ^"theory"^"\n"
      ^"     \""
      ^(if source_of ofmcfp = "" 
	then protocol
	else filename (source_of ofmcfp) )
      ^"\"\n"
      ^" imports"^"\n"
      ^"   \"../src/ofmc\""^"\n"
      ^"begin"^"\n\n"
    end




fun gen_datatype ofmcfp =   
    let  
      fun mk_unique []      = []
        | mk_unique (x::xs) = if (List.exists (fn e => e = x) xs) then (mk_unique xs) else (x::(mk_unique xs))

      val types = types_of ofmcfp

      val agents = sel_types_of "Agent" ofmcfp
      val purposes = sel_types_of "Purpose" ofmcfp

      val numbers = sel_types_of "Number" ofmcfp
      val functions = sel_types_of "Function" ofmcfp
      val symkeys = sel_types_of "SymmetricKey" ofmcfp
 
      fun types2string conv []      = "\n"
	| types2string conv [x]     = (conv x)
	| types2string conv (x::xs) = (conv x)^" | "^(types2string conv xs)

      val purposes = mk_unique (purposes@(map (fn x => "purpose"^x) numbers))
    in
      "datatype Role = "^(types2string (fn r =>  "r"^r)  agents)^"\n\n"
      ^(if purposes = [] 
	then "datatype Purpose = purpose\n"
	else "datatype Purpose = "^(types2string (fn x => x) purposes)^"\n")
      ^"datatype Agent = honest nat\n"         
      ^"               | dishonest nat\n\n"

      ^"datatype Nonce = "^(types2string (fn x => x^"\n") (type_abstraction ofmcfp "Number"))
      ^"       and Msg  = Nonce   \"Nonce\" \n"      
      ^"          | Agent  \"Agent\"     \n"  
      ^"          | Purpose \"Purpose\"\n"
      ^"          | pair  \"Msg*Msg\"    \n" 
      ^"          | scrypt \"Msg*Msg\"   \n"  
      ^"          | crypt  \"Msg*Msg\"   \n"  
      ^"          | inv    \"Msg\"       \n"  
      ^"          | SID    \"nat\"        \n" 
      ^"          | Step   \"nat\"         \n" 
      ^"          | authentication \n"
      ^"          | secrecy \n"
      ^"(* SymKeys *)\n"
      ^"          | SymKey \"Msg\"\n"
      ^(if (type_abstraction ofmcfp "SymmetricKey") = [] then ""
	else ("          | "^(types2string (fn x => x) (type_abstraction ofmcfp "SymmetricKey"))^"\n")) 
      ^"(* Functions *)\n"
      ^(if (type_abstraction ofmcfp "Function") = [] then ""
	else "          | "^(types2string (fn x => x) (type_abstraction ofmcfp "Function"))^"\n") 
(*	else "          | "^(types2string (fn x => x^" \"Msg\"") functions)^"\n") *)
      ^"\n"
      ^"    datatype Fact = Iknows Msg\n"
      ^"                  | State \"Role * (Msg list)\"\n"
      ^"                  | Secret \"Msg * Msg\"\n"
      ^"                  | Attack \"Msg\"\n"
      ^"                  | Witness \"Msg * Msg * Msg * Msg\"\n"
      ^"                  | Request \"Msg * Msg * Msg * Msg * Msg\"\n\n\n"
    end


      fun is_literal ofmcfp (CVariable(n,t)) = let 
	val types = types_of ofmcfp
        val wo_agents = (List.filter (fn (a,b) => a <> "Agent") types)
	val  constants = List.concat (map (fn t => #2 t) wo_agents) 
      in 
	if Int.fromString n = NONE 
	then if ((List.exists (fn n' => n = n') constants )
		 orelse n="ni")
	     then true
	     else false
	else true
      end

      fun collect_msgvars ofmcfp (CVariable(n,t))    = if is_literal ofmcfp (CVariable(n,t))  
						then []
						else [CVariable(n,t)]
	| collect_msgvars ofmcfp (COperator(n,t,ms)) = List.concat (map (collect_msgvars ofmcfp) ms)
	| collect_msgvars ofmcfp (Abstraction(m,a)) = (collect_msgvars ofmcfp m)@(collect_msgvars ofmcfp a)

      fun collect_vars ofmcfp (CState (s,ms)) = List.concat (map (collect_msgvars ofmcfp) ms)
	| collect_vars ofmcfp (CIknows m)    = collect_msgvars ofmcfp m 
	| collect_vars ofmcfp (CAttack ms)    = List.concat (map (collect_msgvars ofmcfp) ms)
	| collect_vars ofmcfp (CWitness ms)  = List.concat (map (collect_msgvars ofmcfp) ms)
	| collect_vars ofmcfp (CRequest ms)  = List.concat (map (collect_msgvars ofmcfp) ms)
	| collect_vars ofmcfp (CSecret ms)   = List.concat (map (collect_msgvars ofmcfp) ms)
	| collect_vars ofmcfp (CFact (s,m))  = collect_msgvars ofmcfp m



fun string_of_cmsg (CVariable (s,t))     = s
  | string_of_cmsg (COperator (s,t,[]))  = s
  | string_of_cmsg (COperator (s,t,ms))  =  s^"("^(string_of_cmsg_list ms)^")"
  | string_of_cmsg (Abstraction (m,n))   = "("^(string_of_cmsg m)^" "^(string_of_cmsg n)^")"

and string_of_cmsg_list []               = ""
  | string_of_cmsg_list [m]              = string_of_cmsg m
  | string_of_cmsg_list (m::ms)          = (string_of_cmsg m)^", "^(string_of_cmsg_list ms) 

	    fun gen_exists [] = ""
	      | gen_exists xs = "? "^(String.concat (map (fn f => string_of_cmsg f^" ") xs))^". \n   "


fun string_of_cfact ofmcfp (CState (s,ms)) = "State("^s^", ["^(string_of_cmsg_list ms)^"] )" 
  | string_of_cfact ofmcfp (CIknows m)     = "Iknows("^(string_of_cmsg m)^")"
  | string_of_cfact ofmcfp (CAttack ms)     = "Attack("^(string_of_cmsg_list ms)^")"
  | string_of_cfact ofmcfp (CWitness ms)   = "Witness("^(string_of_cmsg_list ms)^")"
  | string_of_cfact ofmcfp (CRequest ms)   = "Request("^(string_of_cmsg_list ms)^")"
  | string_of_cfact ofmdfp (CSecret ms)    = "Secret("^(string_of_cmsg_list ms)^")"
  | string_of_cfact ofmdfp (CFact (s,m))  = "Fact("^s^", "^(string_of_cmsg m)^")"
  | string_of_cfact ofmcfp (CNotEqual (n,m))  = "~ ( "^(gen_exists (collect_msgvars ofmcfp m))
					 ^(string_of_cmsg n)^" = "^(string_of_cmsg m)^")"



fun gen_inductive ofmcfp = 
    let
      val protocol = protocol_of ofmcfp
      fun gen_knowledge ((k:(string * Fact))::ks) = 
	  let
	    val protocol = protocol_of ofmcfp
  	    fun string_of_initrule (k:(string * Fact)) = ((#1 k)^": \"[ "
					^(string_of_cfact ofmcfp (deabstractFact ofmcfp (#2 k)))
					^"] : "^protocol^"\"\n")
	  in
	    "   "^(string_of_initrule k)
	    ^(String.concat (map (fn k => " | "^(string_of_initrule k)) ks))
	  end
	  
      fun gen_rules rules = 
	  let
	    val protocol = protocol_of ofmcfp
	    fun string_of_rule (r:Rule) = 
		let
		  val name = case (#1 r) of NONE => "" | SOME s => (s^": ")
		  fun to_string  (CNotEqual (n,m)) = ";\n   "^(string_of_cfact ofmcfp (CNotEqual (n,m))) 
		    | to_string  f =  ";\n   "^(string_of_cfact ofmcfp f)^" : (set t)"
		in
		name^" \"[| t :"^protocol
		^(String.concat (map (fn k => to_string (deabstractFact ofmcfp k)) ((#2 r))  )   )
		^ "|] \n ==> \n("
		^(String.concat (map (fn k => "("^(string_of_cfact ofmcfp (deabstractFact ofmcfp k))^")\n  #") ((#3 r))))
                ^ "t) : "^protocol^"\"\n"
		end
	  in
	    (String.concat (map (fn k => " | "^(string_of_rule k)) rules))
	  end
    in
      "inductive_set\n"
      ^"  "^protocol^"::\"Fact list set\"\n"
      ^"where\n"
      ^(gen_knowledge (knowledge_of ofmcfp))
      ^(gen_rules (rules_of ofmcfp)) 
    end
    

fun gen_fp ofmcfp = 
    let
      val protocol = protocol_of ofmcfp
      val protocolFp = protocol^"_fp"
      val inner_quantification = false                            

                                                            
      fun mk_msgvars_unique (CVariable(n,t))    = if is_literal ofmcfp (CVariable(n,t))  
						  then (CVariable(n,t))
						  else (CVariable(n^(varcount()),t))
	| mk_msgvars_unique (COperator(n,t,ms)) = (COperator(n,t, map mk_msgvars_unique ms))
	| mk_msgvars_unique (Abstraction(m,a))  = (Abstraction(mk_msgvars_unique m,
							       mk_msgvars_unique a))


      fun mk_msgvars_unique' v (CVariable(n,t))    = if is_literal ofmcfp (CVariable(n,t))   
						     then (CVariable(n,t))
						     else 
						       if (v=(CVariable(n,t))) 
						       then (CVariable(n^(varcount()),t))
						       else (CVariable(n,t))
						   


	| mk_msgvars_unique' v (COperator(n,t,ms)) = (COperator(n,t, map (mk_msgvars_unique' v) ms))
	| mk_msgvars_unique' v (Abstraction(m,a))  = (Abstraction(mk_msgvars_unique' v m,
								  mk_msgvars_unique' v a))

		       
      fun mk_vars_unique (CState (s,ms)) = (CState (s, map mk_msgvars_unique ms))
	| mk_vars_unique (CIknows m)     = (CIknows (mk_msgvars_unique m) )
	| mk_vars_unique (CAttack ms)     = (CAttack (map mk_msgvars_unique ms))
	| mk_vars_unique (CWitness ms)   = (CWitness (map mk_msgvars_unique ms))
	| mk_vars_unique (CRequest ms)   = (CRequest (map mk_msgvars_unique ms))
	| mk_vars_unique (CSecret ms)    = (CSecret (map mk_msgvars_unique ms))
	| mk_vars_unique (CFact (s,m))   = (CFact (s,mk_msgvars_unique m))

      fun mk_vars_unique' v (CState (s,ms)) = (CState (s, map (mk_msgvars_unique' v) ms))
	| mk_vars_unique' v (CIknows m)     = (CIknows (mk_msgvars_unique' v m) )
	| mk_vars_unique' v (CAttack ms)    = (CAttack  (map (mk_msgvars_unique' v) ms))
	| mk_vars_unique' v (CWitness ms)   = (CWitness (map (mk_msgvars_unique' v) ms))
	| mk_vars_unique' v (CRequest ms)   = (CRequest (map (mk_msgvars_unique' v) ms))
	| mk_vars_unique' v (CSecret ms)    = (CSecret (map (mk_msgvars_unique' v) ms))
	| mk_vars_unique' v (CFact (s,m))   = (CFact (s,mk_msgvars_unique' v m))


						

      val facts =  (((knowledge_of ofmcfp)@(fixedpoint_of ofmcfp)))
		   
      fun string_of_fp_fact ofmcfp (n,f) = 
	  let
	    val _ = reset_varcount()
	    val cf = mk_vars_unique (deabstractFact ofmcfp  f)
	  in
	    (gen_exists (collect_vars ofmcfp cf))
	    ^  "m = "
	    ^(string_of_cfact ofmcfp  cf)
	  end

      fun string_of_fp_fact' ofmcfp (n,f) = "m = "^(string_of_cfact  ofmcfp f)


      fun mk_outer_exists facts =
	  let
	    fun toSet []      = []
	      | toSet (x::xs) = if List.exists (fn e => x = e) xs 
				then toSet xs
				else x::(toSet xs)
	    fun vars_of facts = toSet (List.concat(map (fn (n,f) => collect_vars ofmcfp f) facts))
	    val vars = vars_of facts
	    fun mk_v_unique [] (n,f) = (n,f)
	      | mk_v_unique (v::vs) (n,f)  = let
		  val _ = reset_varcount() 
		in 
		  mk_v_unique vs (n,mk_vars_unique' v f)
		end
	    val ufacts = map (mk_v_unique vars) facts
	    val uvars = vars_of ufacts
	  in
	    (uvars, ufacts)
	  end
	  val cfacts   = map (fn (n,f) => (n,deabstractFact ofmcfp f)) facts
			 
	  val outer_ex =  mk_outer_exists cfacts
    in
      if inner_quantification 
      then
	( "definition\n" 
	  ^"\""^protocolFp^" = {m. (\n"
	  ^"   ("^(string_of_fp_fact  ofmcfp (hd facts)^")\n")
	  ^(String.concat (map (fn f => " | ("^(string_of_fp_fact ofmcfp f)^")\n") (tl facts) ))
	  ^")}\"\n") 
      else
	( "definition\n"
	  ^"\""^protocolFp^" = {m. ( ? "^(String.concat (map (fn f => string_of_cmsg f^" ") (#1 outer_ex )))^".\n"
	  ^"   ("^(string_of_fp_fact'  ofmcfp (hd (#2 outer_ex ))^")\n")
	  ^(String.concat (map (fn f => " | ("^(string_of_fp_fact' ofmcfp f)^")\n") (tl (#2 outer_ex )) ))
	  ^")}\"\n") 
    end


fun gen_no_attack ofmcfp = 
    let
      val protocol = (protocol_of ofmcfp)
    in
      "lemma fp_attack_free: \"~ (Attack m : "^protocol^"_fp)\"\n"
      ^"  by(simp only: "^protocol^"_fp_def, simp only: set2pred, simp, auto?)+\n\n"
    end

fun gen_over_approx_auto ofmcfp = 
    let
      val protocol = protocol_of ofmcfp 
    in
      "lemma over_approx: \"t :  "^protocol^" ==> (set t) <= "^protocol^"_fp\"\n" 
      ^"  apply(rule "^protocol^".induct, simp_all, safe)\n"
      ^"  apply(propagate_fp, simp add: "^protocol^"_fp_def, simp only: set2pred, simp, auto?)+\n" 
      ^"done\n\n"
    end
    
fun gen_over_approx ofmcfp = 
    let
      val protocol = protocol_of ofmcfp 
      val rulenames = (map (#1) (knowledge_of ofmcfp))@(map (Option.valOf o #1) (rules_of ofmcfp))
      fun gen_cuts rn = "  apply(propagate_fp, cut_tac "^rn^", (assumption | simp)+)\n"
    in
      "lemma over_approx: \"t :  "^protocol^" ==> (set t) <= "^protocol^"_fp\"\n" 
      ^"  apply(rule "^protocol^".induct, simp_all)\n"
      ^(String.concat (map gen_cuts rulenames)) 
      ^"done\n\n"
    end



fun checkfp ofmcfp = 
    let
      val protocol = protocol_of ofmcfp
      fun check_knowledge (k:(string * Fact)) = 
	  let
	    val protocol = protocol_of ofmcfp
	    fun string_of_initrule (k:(string * Fact)) = ((#1 k)^": \""
					^(string_of_cfact ofmcfp (deabstractFact ofmcfp (#2 k)))
					^" : "^protocol^"_fp\"\n")
	  in
	    "lemma "^(string_of_initrule k)
            ^"by(simp only: "^protocol^"_fp_def, simp only: set2pred, simp, auto?)+\n\n"
	  end

(*
	    fun string_of_rule (r:Rule) = 
		let
		  val name = case (#1 r) of NONE => "" | SOME s => (s^": ")
		  fun to_string  (CNotEqual (n,m)) = ";\n   "^(string_of_cfact (CNotEqual (n,m))) 
		    | to_string  f =  ";\n   "^(string_of_cfact f)^" : (set t)"
		in
		name^" \"[| t :"^protocol
		^(String.concat (map (fn k => to_string (deabstractFact ofmcfp k)) ((#2 r))  )   )
		^ "|] \n ==> \n("
		^(String.concat (map (fn k => "("^(string_of_cfact (deabstractFact ofmcfp k))^")\n  #") ((#3 r))))
                ^ "t) : "^protocol^"\"\n"
		end
*)
	  
      fun check_rules (r:Rule) = 
	  let
	    val protocol = protocol_of ofmcfp
	    val name = case (#1 r) of NONE => ":" | SOME s => (s^": ")
	    fun to_string  (CNotEqual (n,m)) = (string_of_cfact ofmcfp (CNotEqual (n,m))) 
	      | to_string  f =  (string_of_cfact ofmcfp f)^" : "^protocol^"_fp"

	  in
	    "lemma "^name^" \"[| "
	    ^(String.concat (map (fn k => "\n  "^(to_string (deabstractFact ofmcfp k))) ([hd (#2 r)])  )   )
	    ^(String.concat (map (fn k => ";\n "^(to_string (deabstractFact ofmcfp k))) (tl (#2 r))  )   )
	    ^ "|] \n ==> "
	    ^(String.concat (map (fn k => "\n ("^(to_string (deabstractFact ofmcfp k))^")") ([hd (#3 r)])))
	    ^(String.concat (map (fn k => " &\n ("^(to_string (deabstractFact ofmcfp k))^")") (tl (#3 r))))
            ^ "\"\n"
	    ^"by(simp only: "^protocol^"_fp_def, simp only: set2pred, simp, auto?)+\n\n"
	  end
    in
       (String.concat (map check_knowledge (knowledge_of ofmcfp)))
      ^(String.concat (map check_rules (rules_of ofmcfp))) 
    end


fun ofmc_thygen ofmcfp = 
    if is_safe ofmcfp 
    then 
    let 
      val protocol = protocol_of ofmcfp
      val _ = print (gen_header ofmcfp)
      val _ = print ("\n\nsection {* Protocol Model ("^protocol^") *}\n")
      val _ = print (gen_datatype ofmcfp)
      val _ = print ("\n\nsection {* Inductive Protocol Definition ("^protocol^") *}\n")
      val _ = print (gen_inductive ofmcfp) 
      val _ = print ("\n\nsection {* Fixed-point Definition ("^protocol^") *}\n")
      val _ = print (gen_fp ofmcfp) 
      val _ = if !noproof then () 
	      else (print ("\n\nsection {* Checking Fixed-point ("^protocol^") *}\n");
		    print (gen_no_attack ofmcfp);
		    print (checkfp ofmcfp);
		    print ("\n\nsection {* Security Proof(s) ("^protocol^") *}\n");
		    print (gen_over_approx ofmcfp))
(*    val _ = print ("(* Alternatively, the following script provides an non-modular\n")
      val _ = print ("   way for proving the over-approximation direclty:\n\n")
      val _ = print (gen_over_approx_auto ofmcfp)
      val _ = print ("*)\n")
*)
      val _ = print ("\n\nend (* theory *)\n")
      in (success,ofmcfp) end
    else (attackOfmc,ofmcfp)

fun ofmc_thygenAnB f = (ofmc_thygen o ofmc_connector.parseAnBFile) f
		     handle _ => (parseError,  OfmcFp.empty_ofmc_fp)

fun print_usage name = let
  val _ = print("\n")
  val _ = print("usage: "^name^" [args] <anb-specification>\n")
  val _ = print(name^", version "^version^"\n")
  val _ = print("\n")
  val _ = print("       --wauth\n")
  val _ = print("       --noproofs\n")
  val _ = print("\n")
in
  ()
end

fun warning s = (TextIO.output (TextIO.stdErr, s); TextIO.flushOut TextIO.stdErr)

fun main (name:string,args:(string list)) = 
    let 
      val prgName = (hd o rev) (String.fields (fn s => s = #"/" orelse s = #"\\") name) 
    in
      (  
       case (prgName,args) of 
	 (n, [])                       => print_usage name
       | (n, "--noproof"::ar)          => (noproof := true ; main(name, ar))
       | (n, "--wauth"::ar)            => (ofmc_connector.wauth  := true ; main(name, ar))
       | (n, [file])                   => if String.isPrefix "-" file
					 then print_usage name
					 else let 
					     val timer =  Timer.startRealTimer ()
	     				     val start = Timer.checkRealTimer timer
					     val (result,fp) = ofmc_thygenAnB file
					     val stop = Timer.checkRealTimer timer
					     val duration = Time.-(stop,start)
					     fun print_result duration result fp = 
						 let 
						   val _ = warning ("\nprotocol:  "^(protocol_of fp)^"\n")
						   val _ = warning ("result:    "^(string_of_result result)^"\n")
						   val _ = warning ("duration:    "^(Time.toString duration)^"\n")
						   val _ = warning ("fixed-point: "
								    ^(Int.toString(List.length (fixedpoint_of fp )))^"\n")
						   val _ = warning ("knowledge:   "
								    ^(Int.toString(List.length (knowledge_of fp )))^"\n")
						 in () end 
					   in
					     print_result duration  result fp
					   end
		    
       | (_,_)                         => print_usage name
      )
    end


end

val _ = ofmc_thygen.main(CommandLine.name(), CommandLine.arguments())
