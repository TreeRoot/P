%namespace PParser
%visibility internal

%parsertype		PParser
%scanbasetype	PScanBase
%tokentype		PTokens

%union {
	public string s;
	public bool b;
	public Ops uop;
	public Ops bop;
	public IDSLStmt stmt;
	public IDSLExp exp;
	public TypeNode type;
	public BaseNode node;
	public int assert;
	public int assume;
	public List<INode> lst;
	public List<IDSLStmt> stmtLst;
	public List<string> slst;
}

%YYSTYPE LexValue
%partial

%token T_INT T_BOOL T_EVENTID T_MACHINEID T_ANY T_SEQ
%token MAIN EVENT MACHINE ASSUME GHOST

%token VAR START FOREIGN STATE FUN ACTION MAXQUEUE SUBMACHINE

%token ENTRY EXIT DEFER IGNORE GOTO ON DO PUSH

%token IF WHILE THIS TRIGGER PAYLOAD ARG NEW RETURN ID LEAVE ASSERT SCALL RAISE SEND DEFAULT DELETE NULL
%token LPAREN RPAREN LCBRACE RCBRACE LBRACKET RBRACKET SIZEOF

%token TRUE FALSE

%token ASSIGN
%token EQ NE LT GT LE GE
%left LAND LNOT LOR

%token DOT COLON COMMA
%left  SEMICOLON

%token INT REAL BOOL


%left  PLUS MINUS
//%left  MOD
%left  DIV
%left  MUL 
%left  UMINUS

// TODO: Fix this mess. It doesn't actually supress the warnings.
%nonassoc PREC_SEQ
%nonassoc PREC_EVERYTHING_ELSE
%nonassoc ELSE

%token maxParseToken 
%token LEX_WHITE LEX_ERROR LEX_COMMENT

%{

void debug(string msg, LexLocation loc) {
	Console.WriteLine(msg);
}

internal class Cast<T1,T2> where T2 : T1
{
	public static IEnumerable<T2> list(IEnumerable<T1> l) {
		foreach (T1 e in l) { yield return (T2)e; }
	}
}

public List<INode> prepend(INode n, List<INode> l) { l.Insert(0, n); return l; }
public List<INode> prependF(LexValue v, List<INode> l) { 
	if (v.lst != null) {
		l.InsertRange(0,v.lst);
	} else {
		l.Insert(0,v.node);
	}
	return l;
}

public void setLoc(INode n, LexLocation l) { n.loc = new DSLLoc(l); }
public void setLoc(INode n, LexLocation s, LexLocation e) { n.loc = new DSLLoc(s.Merge(e)); }
%}
%%

//
//  ----------------  P DSL ---------------------------------------
//

Program
	: PDeclaration Program						{ root.prepend((IPDeclaration)$1.node); setLoc(root, @1, @2);}
	| EOF
	;

PDeclaration
	: EventDecl
	| MachineDecl
	;

// ------------------   Types  ------------------------------------
Type
	: T_INT										{ $$.type = new TypeInt(); setLoc($$.type, @1);}
	| T_BOOL									{ $$.type = new TypeBool(); setLoc($$.type, @1);}
	| T_EVENTID									{ $$.type = new TypeEventID(); setLoc($$.type, @1);}
	| T_MACHINEID								{ $$.type = new TypeMachineID(); setLoc($$.type, @1);}
	| T_ANY										{ $$.type = new TypeAny(); setLoc($$.type, @1);}
	| NamedTupleType
	| TupleType
	| SeqType
	;

NamedTupleType
	: LPAREN FieldTypeList RPAREN				{ $$.type = $2.type; setLoc($$.type, @1, @3);}
	;

FieldTypeList
	: ID COLON Type							{ var t = new TypeNamedTuple(); t.prepend($1.s, $3.type); $$.type = t; setLoc($$.type, @1, @3);}
	| FieldTypeList COMMA ID COLON Type 		{ var t = (TypeNamedTuple)$1.type; t.append($3.s, $5.type); $$.type = t; setLoc($$.type, @1, @5);}
	;

TupleType
	: LPAREN TypeList RPAREN				{ $$.type = $2.type; setLoc($$.type, @1, @3);}
	;

// Explicitly enforcing at least one element in tuple
TypeList
	: Type									{ var t = new TypeTuple(); t.append($1.type); $$.type = t; }
	| Type COMMA TypeList					{ var t = (TypeTuple) $3.type; t.prepend($1.type); $$.type = t; }
	;

SeqType
	: T_SEQ LBRACKET Type RBRACKET			{ $$.type = new TypeSeq($3.type); setLoc($$.type, @1, @4); }
	;

// ------------------   Event Declarations  -------------------------
EventDecl
	: EVENT ID TypeOrNull AnnotationOrNull SEMICOLON	{ if ($3.type != null) {
														$$.node = new EventDeclaration($2.s, $4.assert, $4.assume, $3.type); setLoc($$.node, @1, @5);
													  } else {
														$$.node = new EventDeclaration($2.s, $4.assert, $4.assume); setLoc($$.node, @1, @5);
													  }
													}
	;

AnnotationOrNull
	: ASSERT INT									{ $$.assert = Convert.ToInt32($2.s); $$.assume = -1;}
	| ASSUME INT									{ $$.assert = -1; $$.assume = Convert.ToInt32($2.s); }
	|												{ $$.assert = -1; $$.assume = -1; }
	;

TypeOrNull
	: COLON Type									{ $$.type = $2.type; }
	|												{ $$.type = null; }
	;

// --------------------  Machine Declarations --------------------
MachineDecl
	: IsMain IsGhost MACHINE ID LCBRACE MachineBody RCBRACE	{ $$.node = new MachineDeclaration($4.s, $2.b, $1.b, Cast<INode, IMachineBodyItem>.list($6.lst)); setLoc($$.node, @1, @7);}
	;

IsGhost
	: GHOST											{ $$.b = true;}
	|												{ $$.b = false; }
	;

IsMain
	: MAIN											{ $$.b = true;  }
	|												{ $$.b = false; }
	;

// ---------------------  Machine Bodies   -----------------------
MachineBody
	:												{ $$.lst = new List<INode>(); }
	| MachineBodyItem MachineBody					{ $$.lst = prependF($1, $2.lst); }
	;

MachineBodyItem
	: VarDecl
	| StateDecl
	| ActionDecl
	| FunDecl
	| MaxQueueSizeDecl
	| SubmachineDecl
	;

SubmachineDecl
	: SUBMACHINE ID LCBRACE SubmachineBody RCBRACE  { $$.node = new SubmachineDeclaration($2.s, Cast<INode, StateDeclaration>.list($4.lst)); setLoc($$.node, @1, @5); }
	;

SubmachineBody
	: StateDecl SubmachineBody						{ prepend($1.node, $2.lst); }
	|												{ $$.lst = new List<INode>(); }
	;

MaxQueueSizeDecl
	: MAXQUEUE INT SEMICOLON						{ $$.node = new MaxQueueDeclaration(Convert.ToInt32($2.s)); setLoc($$.node, @1, @3);}
	;
// -------------------   Var Declarations    -------------------
VarList
	: ID											{ $$.slst = new List<string>(); $$.slst.Add($1.s); }
	| ID COMMA VarList								{ $$.slst.Insert(0, $1.s); }
	;

VarDecl
	: IsGhost VAR VarList COLON Type SEMICOLON		{ $$.lst = new List<INode>();
													  foreach (string s in $3.slst) {
														var v = new VarDeclaration($5.type, s, $1.b); $$.lst.Add(v);
														setLoc(v, @1, @6);
													  }
													}
	;

// -------------------   Function Declarations    -------------------
FunDecl
	: IsForeign FUN AttributeOrNull ID Params TypeOrNull StmtBlock	{ $$.node = new FunDeclaration($4.s, $1.b, (TypeNamedTuple) $5.type, $6.type, (DSLBlock)$7.stmt, (DSLAttribute)$3.node); setLoc($$.node, @1, @7); }
	;

Params
	: LPAREN RPAREN									{ $$.type = null; }
	| NamedTupleType
	;

IsForeign
	: FOREIGN										{ $$.b = true; }
	|												{ $$.b = false; }
	;

// ------------------    Action Declaration		----------------------
ActionDecl
	: ACTION ID StmtBlock							{ $$.node = new ActionDeclaration($2.s, (DSLBlock)$3.stmt); }
	;

// ------------------    State Declarations     ----------------------
StateDecl
	: StartOrNull STATE ID LCBRACE StateBody RCBRACE			{ $$.node = new StateDeclaration($3.s, Cast<INode, IStateBodyItem>.list($5.lst), $1.b); setLoc($$.node, @1, @6);}
	;

StartOrNull
	: START														{ $$.b = true; }
	|															{ $$.b = false; }
	;
StateBody
	: 												{ $$.lst = new List<INode>(); }
	| StateBodyItem StateBody						{ $$.lst = prepend($1.node, $2.lst); }
	;

NonDefaultEventList
	: ID										{ $$.slst = new List<string>(); $$.slst.Add($1.s); }
	| ID COMMA EventList						{ var l = $3.slst; l.Insert(0, $1.s); $$.slst = l; }
	;

EventList
	: EventID										{ $$.slst = new List<string>(); $$.slst.Add($1.s); }
	| EventID COMMA EventList						{ var l = $3.slst; l.Insert(0, $1.s); $$.slst = l; }
	;
	
EventID
	: ID
	| DEFAULT
	;

StateBodyItem
	: ENTRY StmtBlock								{ $$.node = new EntryFunction((DSLBlock)$2.stmt); setLoc($$.node, @1, @2);}
	| EXIT StmtBlock								{ $$.node = new ExitFunction((DSLBlock)$2.stmt); setLoc($$.node, @1, @2);}
	| DEFER NonDefaultEventList  SEMICOLON					{ $$.node = new Defer($2.slst); setLoc($$.node, @1, @3);}
	| IGNORE NonDefaultEventList  SEMICOLON					{ $$.node = new Ignore($2.slst); setLoc($$.node, @1, @3);}
	| ON EventList GOTO ID  SEMICOLON				{ $$.node = new Transition($2.slst, $4.s); setLoc($$.node, @1, @5);}
	| ON EventList PUSH ID  SEMICOLON				{ $$.node = new CallTransition($2.slst, $4.s); setLoc($$.node, @1, @5);}
	| ON EventList DO ID SEMICOLON					{ $$.node = new Action($2.slst, $4.s); setLoc($$.node, @1, @5);}
	;

//
// --------------------------------  Function DSL ---------------------------------------
// 
Stmt
	: IF Exp Stmt ELSE Stmt														{ $$.stmt = new DSLITE($2.exp, $3.stmt, $5.stmt); setLoc($$.stmt, @1, @5); }
	| IF Exp Stmt							%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLITE($2.exp, $3.stmt, new DSLSkip()); setLoc($$.stmt, @1, @3); }
	| WHILE Exp Stmt						%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLWhile($2.exp, $3.stmt); setLoc($$.stmt, @1, @3); }
	| Exp ASSIGN Exp SEMICOLON				%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLAssign($1.exp, $3.exp); setLoc($$.stmt, @1, @4); }
	| StmtBlock														%prec PREC_EVERYTHING_ELSE			{ $$.stmt = $1.stmt; }
	| ASSERT LPAREN Exp RPAREN SEMICOLON							%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLAssert($3.exp); setLoc($$.stmt, @1, @5); }
	| SEND LPAREN Exp COMMA Exp OptionalLastArg RPAREN SEMICOLON	%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLSend($3.exp, $5.exp, $6.exp); setLoc($$.stmt, @1, @8); }
	| SCALL LPAREN Exp RPAREN SEMICOLON	%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLSCall($3.exp); setLoc($$.stmt, @1, @5); }
	| RAISE LPAREN Exp OptionalLastArg RPAREN SEMICOLON				%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLRaise($3.exp, $4.exp); setLoc($$.stmt, @1, @6); }
	| FFCall SEMICOLON						%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLFFCallStmt((DSLFFCall)$1.exp); setLoc($$.stmt, @1, @2); }
	| RETURN ExpOrNull SEMICOLON			%prec PREC_EVERYTHING_ELSE          { $$.stmt = new DSLReturn($2.exp); setLoc($$.stmt, @1, @3); }
	| LEAVE SEMICOLON						%prec PREC_EVERYTHING_ELSE          { $$.stmt = new DSLLeave(); setLoc($$.stmt, @1, @2); }
	| SEMICOLON								%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLSkip(); setLoc($$.stmt, @1); } // Allow empty statements
	| DELETE SEMICOLON						%prec PREC_EVERYTHING_ELSE			{ $$.stmt = new DSLDelete(); setLoc($$.stmt, @1, @2); }
	| Exp Args SEMICOLON				    %prec PREC_EVERYTHING_ELSE			{ if (!($1.exp is DSLMember)) {
																					Scanner.yyerror(string.Format("Invalid Expression: '{0}'. Expected function name or variable size container mutation", $1.s));
																				  } else {
																					var op = ($1.exp as DSLMember).member;
																					var baseE = ($1.exp as DSLMember).baseExp;
																					$$.stmt = new DSLMutation(baseE, op, (DSLTuple)$2.exp); setLoc($$.stmt, @1, @3);
																				  }
																				}
	;

OptionalLastArg
	: COMMA Exp																	{ $$.exp = $2.exp; setLoc($$.exp, @1, @2); }
	|																			{ $$.exp = null; }
	;

StmtList
	:																			{ $$.stmtLst = new List<IDSLStmt>(); }
	| StmtList Stmt																{ $$.stmtLst = new List<IDSLStmt>(); $$.stmtLst.AddRange($1.stmtLst); $$.stmtLst.Add($2.stmt); }
	;

StmtBlock
	: LCBRACE StmtList RCBRACE													{
																					var bl = new DSLBlock();
																					foreach (var stmt in $2.stmtLst) {
																						bl.add(stmt);
																					}

																					$$.stmt = bl;
																					setLoc($$.stmt, @1, @3);
																				}
	;

// Expressions. Precedence and associativity attempt to mimic C#. See: http://msdn.microsoft.com/en-us/library/aa691323(v=vs.71).aspx
Unary
	: MINUS	{ $$.uop = Ops.U_MINUS; }
	| LNOT	{ $$.uop = Ops.U_LNOT; }
	;

Multiplicative
	: MUL	{ $$.bop = Ops.B_MUL; }
	| DIV	{ $$.bop = Ops.B_DIV; }
//	| MOD	{ $$.bop = Ops.B_MOD; }
	;

Additive
	: PLUS	{ $$.bop = Ops.B_PLUS; }
	| MINUS { $$.bop = Ops.B_MINUS; }
	;

Relational
	: LT	{ $$.bop = Ops.B_LT; }
	| GT	{ $$.bop = Ops.B_GT; }
	| LE	{ $$.bop = Ops.B_LE; }
	| GE	{ $$.bop = Ops.B_GE; }
	;

Equality
	: EQ	{ $$.bop = Ops.B_EQ; }
	| NE 	{ $$.bop = Ops.B_NE; }
	;

Exp
	: Exp_8
	;

// The following expression definitions from exp_7 to exp_0 are in order of increasing precedence.

Exp_8 // In C# && has a higher precedence than || apparently.
	: Exp_8 LOR Exp_7	{ $$.exp = new DSLBinop(Ops.B_LOR, $1.exp, $3.exp);  setLoc($$.exp, @1, @3); }
	| Exp_7
	;

Exp_7
	: Exp_7 LAND Exp_6	{ $$.exp = new DSLBinop(Ops.B_LAND, $1.exp, $3.exp); setLoc($$.exp, @1, @3); }
	| Exp_6
	;

Exp_6
	: MUL				{ $$.exp = new DSLId("*"); setLoc($$.exp, @1); } // A little bit of a hack to enable * as sugar for non-deterministic boolean choice
	| Exp_5
	;

Exp_5 // Equality Testing
	: Exp_4 Equality Exp_4	{ $$.exp = new DSLBinop($2.bop, $1.exp, $3.exp); setLoc($$.exp, @1, @3); }
	| Exp_4
	;

Exp_4 // Relational
	: Exp_3 Relational Exp_3 { $$.exp = new DSLBinop($2.bop, $1.exp, $3.exp); setLoc($$.exp, @1, @3); }
	| Exp_3
	;

Exp_3 // Additive & Left Assoc
	: Exp_3 Additive Exp_2	{ $$.exp = new DSLBinop($2.bop, $1.exp, $3.exp); setLoc($$.exp, @1, @3); }
	| Exp_2
	;

Exp_2 // Multiplicative & Left Assoc
	: Exp_2 Multiplicative Exp_1	{ $$.exp = new DSLBinop($2.bop, $1.exp, $3.exp); setLoc($$.exp, @1, @3); }
	| Exp_1
	;

Exp_1 // Unary expressions
	: Unary Exp_0	{ $$.exp = new DSLUnop($1.uop, $2.exp); setLoc($$.exp, @1, @2); }
	| Exp_0
	;

Exp_0 // Primary Expresions
	: Exp_0 DOT ID						{ $$.exp = new DSLMember((IDSLExp)$1.exp, $3.s); setLoc($$.exp, @1, @3);  }
	| Exp_0 LBRACKET Exp RBRACKET		    { $$.exp = new DSLIndex((IDSLExp)$1.exp, $3.exp);  setLoc($$.exp, @1, @4); }
	| BaseId							{ $$.exp = new DSLId($1.s); setLoc($$.exp, @1); }
	| INT								{ $$.exp = new DSLInt(Convert.ToInt32($1.s)); setLoc($$.exp, @1); }
	| Bool	
	| NamedTuple							
	| Tuple
	| LPAREN Exp RPAREN					{ $$.exp = $2.exp; setLoc($$.exp, @1, @3); }
	| NewExp
	| Arg
	| FFCall
	| SIZEOF LPAREN Exp RPAREN			{ $$.exp = new DSLSizeof($3.exp); setLoc($$.exp, @1, @4); }
	;

Arg
	: LPAREN Type RPAREN PayloadKw			{ $$.exp = new DSLArg($2.type); setLoc($$.exp, @1, @4); }
	| PayloadKw								{ $$.exp = new DSLArg(null); setLoc($$.exp, @1); }
	;

PayloadKw
	: PAYLOAD | ARG
	;

ExpList
	: Exp								{ var t = new DSLTuple(); t.add($1.exp); $$.exp = t; setLoc($$.exp, @1); }
	| ExpList COMMA Exp					{ var t = (DSLTuple) $1.exp; t.add($3.exp); $$.exp = t; setLoc($$.exp, @1, @3); }
	;

Tuple
	: LPAREN Exp COMMA RPAREN			{ var t = new DSLTuple(); t.add($2.exp); $$.exp = t; setLoc($$.exp, @1, @4); }
	| LPAREN Exp COMMA ExpList RPAREN	{ var t = (DSLTuple) $4.exp; t.prepend($2.exp); $$.exp = t; setLoc($$.exp, @1, @5); }
	;

NamedExpList
	: ID ASSIGN Exp									{ var t = new DSLNamedTuple(); t.append($1.s, $3.exp); $$.exp = t; setLoc($$.exp, @1, @3); }
	| ID ASSIGN Exp COMMA NamedExpList				{ var t = (DSLNamedTuple) $5.exp; t.prepend($1.s, $3.exp); $$.exp = t; setLoc($$.exp, @1, @5); }
	;

NamedTuple
	: LPAREN NamedExpList RPAREN					{ $$.exp = $2.exp; setLoc($$.exp, @1, @3); }
	;

ExpOrNull
	: Exp
	|												{ $$.exp = null; }
	;

NewExp
	: NEW ID KWArgs						{ $$.exp = new DSLNew($2.s, (DSLKWArgs) $3.exp); setLoc($$.exp, @1, @3); }// new instances
	;
Bool
	: TRUE								{ $$.exp = new DSLBool(true); setLoc($$.exp, @1); }
	| FALSE								{ $$.exp = new DSLBool(false); setLoc($$.exp, @1); }
	;

FFCall
	: ID Args							{$$.exp = new DSLFFCall($1.s, (DSLTuple)$2.exp); setLoc($$.exp, @1, @2); } // function call with positional arguments
	;

KWArgList
	: ID ASSIGN Exp						{ var t = new DSLKWArgs(); t.set($1.s, $3.exp); $$.exp = t; setLoc($$.exp, @1, @3);  }
	| ID ASSIGN Exp COMMA KWArgList		{ var t = (DSLKWArgs)$5.exp; t.set($1.s, $3.exp); $$.exp = t; setLoc($$.exp, @1, @5);  }
	;

KWArgs // Function/Construtor invocation arguments
	: LPAREN KWArgList RPAREN			{ $$.exp = $2.exp; setLoc($$.exp, @1, @3); }
	| LPAREN RPAREN						{ $$.exp = new DSLKWArgs(); setLoc($$.exp, @1, @2); }
	;

Args
	: LPAREN ArgList RPAREN				{ $$.exp = $2.exp; setLoc($$.exp, @1, @3); }
	| LPAREN  RPAREN		            { $$.exp = new DSLTuple(); setLoc($$.exp, @1, @2); }
	;

ArgList
	: Exp								{ var t = new DSLTuple(); t.prepend($1.exp); $$.exp = t; setLoc($$.exp, @1); }
	| Exp COMMA ArgList					{ var t = (DSLTuple)$3.exp; t.prepend($1.exp); $$.exp = t; setLoc($$.exp, @1, @3); }
	;

BaseId
	: ID
	| THIS
	| TRIGGER
	| DEFAULT
	| NULL
	;

Attribute
	: LCBRACE ID RCBRACE				{ $$.node = new DSLAttribute($2.s); setLoc($$.node, @1, @3); }
	;

AttributeOrNull
	: Attribute | 
	;
%%