class FiberError < StandardError; end

class Fiber
  def initialize &block
    raise ArgumentError, 'new Fiber requires a block' unless block_given?
    @block = block

    @yield_sem = Dispatch::Semaphore.new(0)
    @resume_sem = Dispatch::Semaphore.new(0)
    
    @fiber_queue = Dispatch::Queue.new "#{__id__}"
    Fiber[@fiber_queue.label]= self    
  end
  
  private
  def execute_block
    @fiber_queue.async do
      @result ||= @block.call(*@args)
      unless self == Fiber[:root_fiber]
        Fiber.delete_fiber(@fiber_queue.label)
        @block = nil # when @block becomes nil the fiber is dead
      end
      @resume_sem.signal
      @result
    end    
  end
  
  
  public
  def resume *args    
    raise FiberError, 'dead fiber called' if @block.nil?
    if (Dispatch::Queue.current.label == @fiber_queue.label && @transfer_state != :re_activated) || @transfer_state == :de_activated
      @resume_sem.signal
      # The following Exceptions are often raised on the @fiber_queue serial dispatch queue
      # When this happens the calling object is unaware of the raised Exception
      # Need a means of raising the Exception on the dispatch queue of the caller
      raise FiberError, 'double resume' if @transfer_state == :de_activated
      raise FiberError, 'dead fiber called'
    end

    if @args.nil?
      @args = args
    else
      @result = args.size > 1 ? args : args.first
    end

    @block_started ? @yield_sem.signal : @block_started = true and execute_block
    @resume_sem.wait unless @transfer_state == :re_activated

    @result
  end
  
  # yield is called from inside the block passed to Fiber.new and executes within the @fiber_queue
  def yield *args
    @result = args.size > 1 ? args : args.first
    @resume_sem.signal
    @yield_sem.wait
    @result
  end
  
  def transfer *args    
    fiber = Fiber.current # the fiber in whose context the transfer call was made. Should be given a yield call to suspend execution of its block
    @transferred_from = fiber
        
    if Fiber[:root_fiber] == fiber # check for transfer to root fiber
      @transfer_state = :activated
      self.resume *args
    else

      resume = Proc.new do |previous_fiber|
        self == previous_fiber ? @transfer_state = :re_activated : @transfer_state = :activated
        self.resume *args
      end
      
      fiber.instance_eval do
        @transfer_state = :de_activated if @transfer_state.nil?
        self.yield *resume.call(@transferred_from)
        @resume_sem.wait if @transfer_state == :re_activated
      end
  
    end
  end
  
  def alive?
    !@block.nil?
  end
  
  def inspect
    "#<#{self.class}:0x#{self.object_id.to_s(16)}>"
  end
  
  def self.current
    Fiber[Dispatch::Queue.current.label] || Fiber[:root_fiber]
  end
  
  def self.yield *args
    raise FiberError, "can't yield from root fiber" unless fiber = Fiber[Dispatch::Queue.current.label]
    fiber.yield *args
  end
  
  # class methods to get, set and delete fiber references
  # wrapped with a serial queue for safe multi-threaded use
  def self.[] fiber_id
    @@fibers_queue.sync { return @@__fibers__[fiber_id] }
  end
  
  def self.[]= fiber_id, fiber
    @@fibers_queue.sync { @@__fibers__[fiber_id]= fiber }
  end
  
  def self.delete_fiber fiber_id
    @@fibers_queue.sync { @@__fibers__.delete(fiber_id) }
  end
  
  @@__fibers__ = {} # create class hash to enable look-up of individual fibers when using 'Fiber.yield'
  @@fibers_queue = Dispatch::Queue.new('fibers_queue') # create serial queue to access class hash
  Fiber[:root_fiber]= Fiber.new { |*args| args.size > 1 ? args : args.first } # create root fiber. Default behaviour is to return arguments it receives  
end