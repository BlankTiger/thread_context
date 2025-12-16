// Caller owns the returned array.
init_threads :: (num_threads: int, proc: Thread_Proc, data: *void = null) -> []Thread {
    threads: [..]Thread;
    array_reserve(*threads, num_threads);
    shared_thread_state := init_shared_thread_state(num_threads);

    for * threads {
        thread_init(it, proc);
        state := init_thread_state(it_index, num_threads, tprint("Worker %", it_index));
        it.starting_context.thread_state        = state;
        it.starting_context.shared_thread_state = shared_thread_state;
        it.data                                 = data;
    }

    return threads;
}

run_threads :: (threads: []Thread) -> []Thread {
    for * threads thread_start(it);
    return threads;
}

// Caller owns the returned array.
run_threads :: (num_threads: int, proc: Thread_Proc, data: *void = null) -> []Thread {
    threads := init_threads(num_threads, proc, data);
    for * threads thread_start(it);
    return threads;
}

run_and_wait_for_threads :: (num_threads: int, proc: Thread_Proc, data: *void = null) {
    threads := inline run_threads(num_threads, proc, data);
    join_threads(threads);
}

// Also deallocs the threads.
join_threads :: (threads: []Thread) {
    for * threads {
        thread_is_done(it, -1);
        thread_deinit(it);
    }

    array_free(threads);
}

init_thread_group :: (num_threads: int, group_proc: Thread_Group_Proc) -> Thread_Group {
    group: Thread_Group;

    init(*group, xx num_threads, group_proc);
    shared_thread_state := init_shared_thread_state(num_threads);

    for * group.worker_info {
        state := init_thread_state(it_index, num_threads, tprint("Worker %", it_index));
        it.thread.starting_context.thread_state        = state;
        it.thread.starting_context.shared_thread_state = shared_thread_state;
    }

    return group;
}
