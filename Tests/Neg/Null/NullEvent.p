main machine Entry {
    var m:mid;
    var e:eid;

    start state init {
        entry {
            m = new Foo();
            e = null;
            send(m, e, null);
        }
    }
}

machine Foo {
    start state init {
    }
}