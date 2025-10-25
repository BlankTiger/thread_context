#scope_module

Lock_Type :: enum #complete { MUTEX; SPIN_LOCK; }

Barrier :: struct(type: Lock_Type) {
    thread_count: int;

    #if type == {
        case .MUTEX;
            mutex:      Mutex;
            cv:         Condition_Variable;
            count:      int;
            generation: int;

        case .SPIN_LOCK;
            // Atomics involved.
            counter: s64;
            sense:   bool;
    }
}

barrier_create :: (thread_count: int, $lock_type: Lock_Type) -> Barrier(lock_type) {
    barrier: Barrier(lock_type);
    barrier.thread_count = thread_count;

    #if lock_type == {
        case .MUTEX;
            init(*barrier.mutex);
            init(*barrier.cv);

        case .SPIN_LOCK;
    }

    return barrier;
}

barrier_destroy :: (barrier: *Barrier($lock_type)) {
    #if lock_type == {
        case .MUTEX;
            destroy(*barrier.mutex);
            destroy(*barrier.cv);

        case .SPIN_LOCK;
    }
}

barrier_sync :: (barrier: *Barrier($lock_type)) {
    #if lock_type == {
        case .SPIN_LOCK;
            local_sense := !barrier.sense;

            arrived := atomic_add(*barrier.counter, 1);

            if arrived == barrier.thread_count - 1 {
                barrier.counter = 0;
                barrier.sense   = local_sense;
            } else {
                while barrier.sense != local_sense {
                    // spin
                }
            }

        case .MUTEX;
            lock(*barrier.mutex);
            defer unlock(*barrier.mutex);

            local_gen := barrier.generation;
            barrier.count += 1;

            if barrier.count == barrier.thread_count {
                barrier.generation += 1;
                barrier.count = 0;
                wake_all(*barrier.cv);
            } else {
                while local_gen == barrier.generation {
                    wait(*barrier.cv, *barrier.mutex);
                }
            }
    }
}
