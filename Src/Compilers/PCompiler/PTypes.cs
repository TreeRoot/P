﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DemoCompiler
{
    abstract class PType
    {
        public abstract override bool Equals(object obj); // Compares types for structural equality
        public static bool operator ==(PType a, PType b)
        {
            if ((((object)a) == null) && (((object)b) == null))
                return true;

            if ((((object)a) == null) || (((object)b) == null))
                return false;

            return a.Equals(b);
        }

        public static bool operator !=(PType a, PType b) { return !(a == b); }

        private static Dictionary<string, PType> nameToPrimType;

        static PType()
        {
            nameToPrimType = new Dictionary<string, PType>();

            nameToPrimType[PData.Cnst_Nil.Node.Name] = new PNilType();
            nameToPrimType[PData.Cnst_Bool.Node.Name] = new PBoolType();
            nameToPrimType[PData.Cnst_Int.Node.Name] = new PIntType();
            nameToPrimType[PData.Cnst_Id.Node.Name] = new PIdType();
            nameToPrimType[PData.Cnst_Event.Node.Name] = new PEventType(null);
            nameToPrimType[PData.Cnst_State.Node.Name] = new PStateType();

            Nil = new PNilType();
            Any = new PAnyType();
            Int = new PIntType();
            Bool = new PBoolType();
            Id = new PIdType();
            Event = new PEventType(null);
            State = new PStateType();
        }

        public abstract bool isSubtypeOf(PType t);
        public abstract PType LUB(PType other);

        public static PType primtiveTypeFromName(string s)
        {
            if (!nameToPrimType.ContainsKey(s))
                throw new NotImplementedException("Unknown primitive type " + s);

            return nameToPrimType[s];
        }

        public static readonly PNilType Nil;
        public static readonly PAnyType Any;
        public static readonly PBoolType Bool;
        public static readonly PIntType Int;
        public static readonly PIdType Id;
        public static readonly PEventType Event;
        public static readonly PStateType State;

        protected static readonly int NilHash = 2;
        protected static readonly int IntHash = 3;
        protected static readonly int BoolHash = 5;
        protected static readonly int IdHash = 7;
        protected static readonly int EventHash = 11;
        protected static readonly int StateHash = 13;

        protected static readonly int AnyHash = 17;

        protected static readonly int TupleHash = 19;
        protected static readonly int NamedTupleHash = 23;
        protected static readonly int SeqHash = 29;

        public static PType computeLUB(IEnumerable<PType> ts)
        {
            if (ts.Count() == 0)
            {
                return PType.Nil; // TODO: REVISIT THIS DECISION!
            }
            else if (ts.Count() == 1)
                return ts.Single();
            else
                return ts.Aggregate(ts.First(), (acc, el) => acc.LUB(el));
        }

        public bool realtive(PType other)
        {
            return this == other || this.isSubtypeOf(other) || other.isSubtypeOf(this);
        }
    }

    // Primitive built in types - int,bool, eid, mid, state
    // Even though we cannot declare variables of type state, we still
    // have an explicit type in the hierarchy. This may be more useful
    // in the future if we decide to allow state variables.
    abstract class PPrimitiveType : PType
    {
        private string pDataName;
        public string name { get { return pDataName; } }

        public PPrimitiveType(string pdataName) { this.pDataName = pdataName; }

        public override bool Equals(object obj)
        {
            return (obj != null && obj is PPrimitiveType &&
                (obj as PPrimitiveType).pDataName == pDataName);
        }

        public override int GetHashCode()
        {
            if (this is PNilType)
                return PType.NilHash;
            if (this is PIntType)
                return PType.IntHash;
            if (this is PBoolType)
                return PType.BoolHash;
            if (this is PIdType)
                return PType.IdHash;
            if (this is PEventType)
                return PType.EventHash;
            if (this is PStateType)
                return PType.StateHash;

            throw new NotImplementedException("Unknown Primitive Type " + this);
        }

        public override string ToString()
        {
            return pDataName;
        }

        public override bool isSubtypeOf(PType t)
        {
            return this.Equals(t) || (t is PAnyType);
        }

        public override PType LUB(PType other)
        {
            if (this == other)
                return this;
            else
                return PType.Any;
        }
    }

    // Encompasses Tuples, Named Tuples, Sets, Sequneces, Dictionaries
    abstract class PCompoundType : PType { }

    class PNilType : PPrimitiveType
    {
        public PNilType() : base(PData.Cnst_Nil.Node.Name) { }

        public override bool isSubtypeOf(PType t)
        {
            return this.Equals(t) || (t is PAnyType) ||
                (t is PIdType) || (t is PEventType);
        }

        public override PType LUB(PType other)
        {
            if (other is PNilType || other is PIdType || other is PEventType)
                return other;
            else
                return PType.Any;
        }
    }

    class PIntType : PPrimitiveType
    {
        public PIntType() : base(PData.Cnst_Int.Node.Name) { }
    }
    class PBoolType : PPrimitiveType
    {
        public PBoolType() : base(PData.Cnst_Bool.Node.Name) { }
    }
    class PIdType : PPrimitiveType
    {
        public PIdType() : base(PData.Cnst_Id.Node.Name) { }
    }

    class PEventType : PPrimitiveType
    {
        public string evtName { private set; get; }

        public PEventType(string eName) : base(PData.Cnst_Event.Node.Name) {
            evtName = eName;
        }
    }

    class PStateType : PPrimitiveType
    {
        public PStateType() : base(PData.Cnst_State.Node.Name) { }
        public override bool isSubtypeOf(PType t)
        {
            return this.Equals(t); // Don't allow states to creep into variables of type Any.
        }

        public override PType LUB(PType other)
        {
            // State Type is special since its not a subtype of any. Therefore if it breaks the
            // upper bound in our type system. Therefore we have to carefully guard it from sneaking
            // into LUB computations.
            throw new Exception("State type snuck into the LUB computation!");
        }
    }

    class PTupleType : PCompoundType
    {
        List<PType> els;

        public PTupleType(IEnumerable<PType> els)
        {
            this.els = new List<PType>(els);
        }

        public override bool Equals(object obj)
        {
            PTupleType other = obj as PTupleType;
            if (((object)other) == null)
                return false;

            if (this.els.Count != other.els.Count) return false;

            for (int i = 0; i < this.els.Count; i++)
                if (!this.els[i].Equals(other.els[i]))
                    return false;

            return true;
        }

        public override int GetHashCode()
        {
            return PType.TupleHash * els.Aggregate(1, (c, e) => c * e.GetHashCode());
        }

        public IEnumerable<PType> elements { get { return els; } }

        public override string ToString()
        {
            var innerS = els.Aggregate("", (a, e) => a + "," + e.ToString());
            
            return "(" + (innerS.Length > 0 ? innerS.Substring(1) : "") + ")";
        }

        public override bool isSubtypeOf(PType t)
        {
            if (t is PAnyType || Equals(t))
                return true;

            if (!(t is PTupleType))
                return false;

            PTupleType otherTup = (PTupleType)t;

            if (els.Count != otherTup.els.Count) return false;

            for (int i = 0; i < els.Count; i++)
                if (!els[i].isSubtypeOf(otherTup.els[i]))
                    return false;

            return true;
        }

        public override PType LUB(PType other)
        {
            if (!((other is PTupleType) && ((PTupleType) other).elements.Count() == this.elements.Count()))
                return PType.Any;

            return new PTupleType(this.elements.Zip(((PTupleType) other).elements, (t1, t2) => t1.LUB(t2)));
        }
    }

    class PNamedTupleType : PCompoundType
    {
        List<Tuple<string, PType>> els;

        public PNamedTupleType(IEnumerable<Tuple<string, PType>> els)
        {
            this.els = new List<Tuple<string, PType>>(els);
            // Sorting the fields lexicographically by name allows us to disregard the order in which they are
            // specified in the named tuple type definition
            this.els.Sort(new Comparison<Tuple<string,PType>>((t1,t2) => Comparer<string>.Default.Compare(t1.Item1, t2.Item1)));
        }

        public override bool Equals(object obj)
        {
            PNamedTupleType other = obj as PNamedTupleType;
            if (((object)other) == null)
                return false;

            if (this.els.Count != other.els.Count) return false;

            for (int i = 0; i < this.els.Count; i++)
                if (!this.els[i].Equals(other.els[i]))
                    return false;

            return true;
        }

        public override int GetHashCode()
        {
            return PType.NamedTupleHash * els.Aggregate(1, (c, e) => c * e.Item1.GetHashCode() * e.Item2.GetHashCode()); // TODO: Is this hashing good?
        }

        public IEnumerable<Tuple<string, PType>> elements { get { return els; } }

        public override string ToString()
        {
            return "(" + (els.Aggregate("", (a, e) => a + "," + e.Item1 + ":" + e.Item2.ToString())).Substring(1) + ")";
        }

        public override bool isSubtypeOf(PType t)
        {
            if (t is PAnyType || this.Equals(t))
                return true;

            if (!(t is PNamedTupleType))
                return false;

            PNamedTupleType other = t as PNamedTupleType;

            if (els.Count != other.els.Count) return false;

            for (int i = 0; i < this.els.Count; i++)
                if (els[i].Item1 != other.els[i].Item1 ||
                    !els[i].Item2.isSubtypeOf(other.els[i].Item2))
                    return false;

            return true;
        }


        public override PType LUB(PType other)
        {
            if (!((other is PNamedTupleType) && ((PNamedTupleType)other).els.Count() == this.els.Count()))
                return PType.Any;

            PNamedTupleType otherT = (PNamedTupleType)other;
            // Check fields names match up.
            if (!this.els.Select(el => el.Item1).Equals(otherT.els.Select(el => el.Item1)))
                return PType.Any;

            return new PNamedTupleType(this.els.Zip(((PNamedTupleType)other).els, (f1, f2) => new Tuple<string, PType>(f1.Item1, f1.Item2.LUB(f2.Item2))));
        }
    }

    class PAnyType : PType
    {
        public PAnyType() { }

        public override bool Equals(object obj)
        {
            return (obj != null && obj is PAnyType);
        }

        public override int GetHashCode()
        {
            return PType.AnyHash;
        }

        public override string ToString()
        {
            return "any";
        }

        public override bool isSubtypeOf(PType t)
        {
            return t is PAnyType;
        }

        public override PType LUB(PType other)
        {
            return PType.Any;
        }       
    }

    class PSeqType : PCompoundType
    {
        PType innerT;
        public PSeqType(PType inner)
        {
            this.innerT = inner;
        }

        public override bool Equals(object obj)
        {
            PSeqType other = obj as PSeqType;
            if (((object)other) == null)
                return false;

            return this.innerT.Equals(other.innerT);
        }

        public override int GetHashCode()
        {
            return PType.SeqHash * innerT.GetHashCode();
        }

        public override string ToString()
        {
            return "seq[" + innerT.ToString() + "]";
        }

        public override bool isSubtypeOf(PType t)
        {
            if (t is PAnyType || this.Equals(t))
                return true;

            if (!(t is PSeqType))
                return false;

            return this.innerT.isSubtypeOf((t as PSeqType).innerT);
        }

        public override PType LUB(PType other)
        {
            if (!(other is PSeqType))
            {
                return PType.Any;
            }
            else
            {
                return new PSeqType(this.innerT.LUB((other as PSeqType).innerT));
            }
        }

        public PType T { get { return innerT; } }
    }
}