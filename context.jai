Shared_Thread_State :: struct {
    barrier_mutex:     Barrier(.MUTEX);
    barrier_spin_lock: Barrier(.SPIN_LOCK);
    // TODO: Maybe make this dynamic, but I don't think that it's really necessary.
    broadcast_memory:  [BROADCAST_MEMORY_SIZE]u8;
}

Thread_State :: struct {
    thread_name:    string;
    lane_idx:       int;
    lane_count:     int;
    lane_lock_type: Lock_Type;

    _pool:        Flat_Pool;
    scratch_pool: Allocator;
}

#add_context thread_state:        *Thread_State;
#add_context shared_thread_state: *Shared_Thread_State;

init_thread_context :: () {
    inline init_thread_context(0, 1, "Main Thread");
}

init_thread_context :: (lane_idx: int, lane_count: int, thread_name: string) {
    context.thread_state = inline init_thread_state(lane_idx, lane_count, thread_name);
}

init_thread_state :: (lane_idx: int, lane_count: int, thread_name: string) -> *Thread_State {
    state := New(Thread_State);

    a: Allocator;
    a.proc = flat_pool_allocator_proc;
    a.data = *state._pool;

    state.scratch_pool = a;
    state.lane_idx     = lane_idx;
    state.lane_count   = lane_count;
    state.thread_name  = thread_name;

    return state;
}

init_shared_thread_state :: (num_threads: int) -> *Shared_Thread_State {
    state := New(Shared_Thread_State);
    state.barrier_mutex     = barrier_create(num_threads, .MUTEX);
    state.barrier_spin_lock = barrier_create(num_threads, .SPIN_LOCK);
    return state;
}

get_scratch :: inline () -> Allocator {
    return context.thread_state.scratch_pool;
}

set_thread_name :: inline (name: string) {
    context.thread_state.thread_name = name;
}

get_thread_name :: inline () -> string {
    return context.thread_state.thread_name;
}

lane_idx :: inline () -> int {
    return context.thread_state.lane_idx;
}

lane_count :: inline () -> int {
    return context.thread_state.lane_count;
}

set_lane_lock_type :: inline (lock_type: Lock_Type) {
    context.thread_state.lane_lock_type = lock_type;
}

lane_range :: inline (count: int) -> start: int, one_past_end: int {
    thread_idx   := lane_idx();
    thread_count := lane_count();

    values_per_thread     := count / thread_count;
    leftover_values_count := count % thread_count;
    thread_has_leftover   := thread_idx < leftover_values_count;
    leftovers_before_this_thread_idx := ifx thread_has_leftover then thread_idx else leftover_values_count;

    thread_first_value_idx := values_per_thread * thread_idx + leftovers_before_this_thread_idx;
    thread_opl_value_idx   := thread_first_value_idx + values_per_thread + (ifx thread_has_leftover then 1 else 0) - 1;  // -1 because jai ranges are end inclusive and we don't wanna overstep any boundaries ofc
    return thread_first_value_idx, thread_opl_value_idx;
}

lane_sync :: inline () {
    if context.thread_state.lane_lock_type == {
        case .MUTEX;     inline barrier_sync(*context.shared_thread_state.barrier_mutex);
        case .SPIN_LOCK; inline barrier_sync(*context.shared_thread_state.barrier_spin_lock);
    }
}

lane_sync_ptr :: (ptr: *$T, src_lane_idx: int) {
    max_broadcast_size := context.shared_thread_state.broadcast_memory.count;
    broadcast_size := size_of(T);

    assert(broadcast_size <= max_broadcast_size, "Broadcast size % exceeds maximum %", broadcast_size, max_broadcast_size);

    shared := context.shared_thread_state;

    if lane_idx() == src_lane_idx {
        memcpy(shared.broadcast_memory.data, ptr, broadcast_size);
    }

    if context.thread_state.lane_lock_type == {
        case .MUTEX;     barrier_sync(*shared.barrier_mutex);
        case .SPIN_LOCK; barrier_sync(*shared.barrier_spin_lock);
    }

    if lane_idx() != src_lane_idx {
        memcpy(ptr, shared.broadcast_memory.data, broadcast_size);
    }

    if context.thread_state.lane_lock_type == {
        case .MUTEX;     barrier_sync(*shared.barrier_mutex);
        case .SPIN_LOCK; barrier_sync(*shared.barrier_spin_lock);
    }
}

#scope_file

#import "Basic";
#import "Flat_Pool";
#import "Thread";
#import "Atomics";
