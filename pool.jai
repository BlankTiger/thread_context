Thread_Pool :: struct {
    threads:             []Thread;
    shared_thread_state: *Shared_Thread_State;
    proc:                Thread_Proc;
    user_data:           *void;
    should_exit:         bool;

    work_semaphore: Semaphore;
    work_in_flight: s64;
}

thread_pool_create :: (num_threads: int, proc: Thread_Proc, user_data: *void = null) -> *Thread_Pool {
    pool := New(Thread_Pool);

    pool.threads             = NewArray(num_threads, Thread);
    pool.shared_thread_state = init_shared_thread_state(num_threads);
    pool.proc                = proc;
    pool.user_data           = user_data;
    pool.should_exit         = false;

    init(*pool.work_semaphore);

    for * pool.threads {
        thread_init(it, thread_pool_proc);
        state := init_thread_state(it_index, num_threads, tprint("Thread pool worker %", it_index));

        it.starting_context.thread_state        = state;
        it.starting_context.shared_thread_state = pool.shared_thread_state;
        it.data                                 = pool;

        thread_start(it);
    }

    return pool;
}

thread_pool_destroy :: (pool: *Thread_Pool) {
    pool.should_exit = true;

    for 0..pool.threads.count - 1 {
        signal(*pool.work_semaphore);
    }

    for * pool.threads {
        thread_is_done(it, -1);
        thread_deinit(it);
    }

    destroy(*pool.work_semaphore);
    array_free(pool.threads);
}

thread_pool_run_and_wait :: (pool: *Thread_Pool, user_data: *void) {
    inline thread_pool_run(pool, user_data);
    inline thread_pool_wait(pool);
}

thread_pool_wait_and_run :: (pool: *Thread_Pool) {
    inline thread_pool_wait(pool);
    inline thread_pool_run(pool, user_data);
}

thread_pool_set_user_data :: inline (pool: *Thread_Pool, user_data: *void) {
    pool.user_data = user_data;
}

thread_pool_run :: (pool: *Thread_Pool, user_data: *void, loc := #caller_location) {
    assert(thread_pool_is_done(pool), "Called %, but thread_pool isn't done working yet.", context.stack_trace.info.name, loc);

    if user_data pool.user_data = user_data;

    atomic_add(*pool.work_in_flight, pool.threads.count);

    for 0..pool.threads.count - 1 {
        signal(*pool.work_semaphore);
    }
}

thread_pool_wait :: (pool: *Thread_Pool) {
    while !thread_pool_is_done(pool) {
        // I think spinning here is more acceptable than having a random sleep
        // sleep_milliseconds(1);
    }
}

thread_pool_is_done :: (pool: *Thread_Pool) -> bool {
    return atomic_read(*pool.work_in_flight) == 0;
}

#scope_file

thread_pool_proc :: (thread: *Thread) -> s64 {
    pool := cast(*Thread_Pool) thread.data;

    while true {
        wait_for(*pool.work_semaphore);

        if pool.should_exit break;

        pool.proc(thread);

        atomic_add(*pool.work_in_flight, -1);
    }

    return 0;
}

#import "Basic";
#import "Thread";
#import "Atomics";
