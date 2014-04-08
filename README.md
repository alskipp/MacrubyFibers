Macruby Fibers
===

Ruby 1.9 [Fibers](http://ruby-doc.org/core-1.9.3/Fiber.html) in Macruby using [Grand Central Dispatch](http://developer.apple.com/library/mac/#documentation/Performance/Reference/GCD_libdispatch_Ref/Reference/reference.html]) (GCD).


### Is it worth it?
Perhaps. The goal was to pass as many of the spec tests as possible (nearly there). The implementation will certainly not be as lightweight as MRI, but it should allow Fiber code to run.

### Implementation Info
Each fiber is given its own serial dispatch queue which is suspended and resumed as needed. Consequently, this means that each fiber is backed by a thread (which is not the case in MRI Ruby). However as GCD is in control of thread creation and allocation, this does not necessarily mean that a new thread is created every time a Fiber is created. GCD can reuse threads that were created for Fibers which have subsequently been used and are no longer alive. Threads can not be reallocated to new Fibers if previous Fibers are still alive, which means it is possible that multitudes of threads will be created in certain circumstances.

Threads will not be created or reallocated until a fiber has been resumed, therefore, 100 threads will NOT be immediately created if 100 Fibers are created.

### Results from running Fibers Rubyspec:
4 files, 25 examples, 51 expectations, 3 failures, 0 errors

##### "raises a FiberError when transferring to a Fiber which resumes itself"
The FiberError is raised, but on a different dispatch queue to the caller. Need to somehow raise the error on the same dispatch queue as the caller.

##### "raises a LocalJumpError if the block includes a return statement"
Not implemented - test causes a Macruby crash - EXC_CRASH (SIGABRT)

##### "raises a LocalJumpError if the block includes a break statement"
Not implemented

Macruby does not currently raise LocalJumpError errors for the following code:

    pr = Proc.new { break }
    pr.call
    
    pr = Proc.new { return }
    pr.call # causes uncaught Objective-C/C++ exception... EXC_CRASH (SIGABRT)

Therefore, LocalJumpError can not currently be implemented within MacrubyFibers.

### Other Known Issues
There is a variable scoping issue when using Macruby with GCD queues which can cause an EXC_BAD_ACCESS crash when mutating a collection class object that is a local variable. Instance variables and global variables are not affected and can be safely mutated. This also applies to Macruby Fibers. Examples below:

    # The following code can currently cause a crash, or unexpected results
    a = []
    f = Fiber.new { a << 1 }
    f.resume
    
    # The following 2 examples are safe
    @a = []
    f = Fiber.new { @a << 1 }
    f.resume
    
    # or:
    $a = []
    f = Fiber.new { $a << 1 }
    f.resume

Due to this current issue, the Ruby Fiber specs have been adjusted to use instance variables (rather than local variables) for any test that involves mutating an array. If mspec tests are run using the unadjusted Ruby Fiber specs, a crash will occur.