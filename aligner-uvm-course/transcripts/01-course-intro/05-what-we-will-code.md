# What we will code

*Chapter: Course introduction · source: attached*

Hi, my name is Christian Slav and this is the first part of the tutorial called Environment Coding Kick-Off.
This is the lecture part.
The majority of our tutorials from now on will be split in two.
The first part will be the lecture like this one, in which we will talk about what we will code.
And the second part will be the practice in which we will code together, whatever we learn in the first lesson.
So let's get started.
In this tutorial we will talk how to build the basic framework required for us in order to build this entire verification environment.
And this basic framework is made out of this part the Testbench, the test and the environment the Testbench will have inside the instance of our aligner the duty.
But in order to make this work, it requires some basic stuff.
For example, it requires a clock generator which will produce a signal like this one.
So the clock is a periodic signal.
An initial reset generator, which will create a reset signal like this one in order to reset all the registers and the logic to start the UVM.
And this implies a simple call to a function called run test.
And when you call this function, there are two important things happening.
The UVM test will be instantiated and it will run the UVM phases.
Let's focus on this first part.
Instantiate the UVM test.
Remember that I told you that in the Testbench we will have the test, but we will not actually write any line of code which will create an instance of our test class.
This will be done automatically by UVM and let's see how this is done.
You can imagine that we will have to write many tests in order to verify our duty and for example, in our case, we will build like a register access test, a random test, and an illegal Eric's access test.
By the way, it's somehow a standard in the industry to use as a prefix for all your files and class names.
Something like this a short name for the company, in our case CFS.
A short name for the duty that you will have to verify in our case a liner and then the rest of the name.
So this is why you will see all the files and all the classes using this prefix.
Let's get back to our problem of how UVM starts the test.
We can tell UVM what test to start by calling this run test function with a string argument, and the value of the string should be the name of the test class.
So, for example, if we want to start this test, this register access test, then the string will have the value of the name of the class.
But this is one way to start a test using the UVM mechanism.
There is another option in which we call run test with an empty string, but we specify the name of the test class in an plus argument.
This plus argument is an argument with which we can invoke the simulator.
All the simulators, like from cadence.
Synopsys mentor, support this feature so you can invoke the simulator with plus UVM test name equals and then the name of the test class.
And in this way, UVM will know that it will have to start this register access test.
In our case, we will use this second option.
And also in a real project, the second option will be used because this is more flexible.
You don't have to modify the systemverilog code of your test testbench.
In order to change the test, you simply invoke the simulator with some different argument.
So if you invoke the simulator like so, UVM will instantiate this particular test.
But one important thing for this entire mechanism to work is that all your tests will have to inherit from a base class called UVM test, and this base class is defined under the UVM package.
Let's move to the second thing done by the call to the run test, which is running the UVM phases.
UVM has nine phases and these are build.
Connect.
End of elaboration, start of simulation, run, extract, check, report and final.
These phases are nothing more than some functions called in this particular order, and for each of them there is a function associated.
Out of all of these, run phase is the only one, which is a task because we should consume time during the simulation.
During run phase and the rest are functions.
All these phases are defined under another class part of the UVM package called UVM component.
This UVM component is a special class because it must be the parent of all our classes, which are part of our environment architecture.
And by the way, also UVM test inherits from UVM component.
So all our tests will also inherit from UVM component.
And by the way, we refer to any class that we define which inherits from UVM component as a component.
If we go back to our picture of the environment, you can identify all the components as blue square.
So all these are actually components they will inherit from that UVM component.
One special thing about any component is that it can only be created in one phase.
In the build phase, once we move out of the build phase, then the structure of our environment is fixed.
Those components will exist in this form up to the end of our simulation.
UVM will call those phase functions in the following way.
When it is in the build phase, it will call build phase for all the components.
When this is done, it will move to the connect phase and then it will call connect phase of all the components and so on.
Out of these nine phases, most of the time you will actually use only three build phase, because in this one we will actually create the instances of all these components connect phase, because in this phase, we will create those connections between our components and run phase.
As in this phase we will actually start our simulation.
So these are the parts that we will build in the test bench.
Now let's move to the test.
As we discussed, we will build this register access test which needs to inherit from UVM test.
But we will have other tests in order to verify different features of our duty.
All these tests will have to have an instance of our environment.
But because we don't really want to have the code which instantiate the environment in all of them, we will put here an intermediate class called base test, and in this one we will create the instance of our environment.
And all of our tests will inherit from this base test.
That's about it.
Let's recap on what we talked about.
So we discussed about the initial environment structure and how to start UVM tests and phases.
And in the next tutorial we will code together all the stuff that we talked about in this tutorial.
Thanks for watching and see you in the next tutorial.
Bye!
