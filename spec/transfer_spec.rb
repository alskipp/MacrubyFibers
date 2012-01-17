require File.expand_path('../spec_helper', __FILE__)
require File.expand_path('../resume', __FILE__)

describe "Fiber#transfer" do
  it_behaves_like :fiber_resume, :transfer
end

describe "Fiber#transfer" do
  it "transfers control from one Fiber to another when called from a Fiber" do
    fiber1 = Fiber.new { :fiber1 }
    fiber2 = Fiber.new { fiber1.transfer; :fiber2 }
    fiber2.resume.should == :fiber1
  end

  it "can be invoked from the same Fiber it transfers control to" do
    @states = []
    fiber = Fiber.new { @states << :start; fiber.transfer; @states << :end }
    fiber.transfer
    @states.should == [:start, :end]
    
    @states = []
    fiber = Fiber.new { @states << :start; fiber.transfer; @states << :end }
    fiber.resume
    @states.should == [:start, :end]
  end

  it "can transfer control to a Fiber that has transfered to another Fiber" do
    @states = []
    fiber1 = Fiber.new { @states << :fiber1 }
    fiber2 = Fiber.new { @states << :fiber2_start; fiber1.transfer; @states << :fiber2_end}
    fiber2.resume.should == [:fiber2_start, :fiber1]
    fiber2.transfer.should == [:fiber2_start, :fiber1, :fiber2_end]
  end
  
  # additional test
  it "can transfer control to a Fiber passed as argument" do
    @states = []
    fiber1 = Fiber.new do |fiber|
      @states << :fiber1_start
      fiber.transfer(Fiber.current)
      @states << :fiber1_finishing
      :fiber1_end
    end
    fiber2 = Fiber.new do |fiber|
      @states << :fiber2_start
      fiber.transfer
      @states << :fiber2_finishing
      :fiber2_end
    end

    fiber1.resume(fiber2).should == :fiber1_end
    @states.should == [:fiber1_start, :fiber2_start, :fiber1_finishing]

    fiber2.resume.should == :fiber2_end
    @states.should == [:fiber1_start, :fiber2_start, :fiber1_finishing, :fiber2_finishing]
  end

  it "raises a FiberError when transferring to a Fiber which resumes itself" do
    fiber = Fiber.new { fiber.resume }
    lambda { fiber.transfer }.should raise_error(FiberError)
  end
end
