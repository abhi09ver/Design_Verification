# What is design verification

*Chapter: Course introduction · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about what is design verification.
The image that you see is a silicon wafer which is used in one of the final stages in a chip production.
A silicon wafer is a disk made from semiconductor material like silicon where the same chip is printed repeatedly.
If you look closely at this picture you will notice a repeated pattern.
Each pattern represents a single chip.
Between the rows and columns, there is connectivity that allows engineers to access individual chips on the wafer.
This is done to run tests and to identify manufacturing issue and this is known as post silicon verification.
Once the post silicon verification is complete, then the wafer is cut up, the chips are extracted, packaged with all the pins attached and prepared for sale.
However, in this training we'll focus on verifying designs before the wafer even exists.
So let's see what we have at that stage in the production of a chip.
If we look at the specifications of a chip, we will find inside a picture which looks like this one.
This is called a block diagram and it is a logical representation of all the modules which are part of this chip.
All these modules are implemented by designers in a language like Verilog or VHDL.
This is called RTL code.
RTL stands for Register Transfer Level.
During pre silicon verification, we ensure that this RTL code works correctly.
There are many stages in pre silicon verification, but one of the first step is to ensure that each of these modules taken as a standalone entity works correctly.
When we verify individual modules part of an entire chip, this is called module level verification.
Normally, we have to do this for all or for most of the modules part of a chip.
After we verify each of these modules, we need to put them together and verify the entire system.
This is called system level verification.
I mentioned several types of verification which we need to do during the production of a chip, but let's see all these types in a more structured manner.
We can split the design verification into two branches.
The first one is called pre silicon verification and in here we are verifying the RTL code.
The second branch is called post silicon verification and in here we verify the actual chip.
We can further split pre silicon verification into two branches.
The first one is module level verification.
In here we are verifying individual modules part of the entire chip.
And then we have system level verification where we verify the entire chip, so all the modules put together must function correctly.
For module level verification, there are different approaches that we can take.
We can either implement the verification as simulation based.
In this approach, we drive the inputs of the module in a simulator and we see what are the outputs produced by that module.
But we can also verify a module using formal verification.
In the formal approach, we write assertions to verify different parts of the module.
Also, formal can be split into several branches like property checking, connectivity checking and so on.
The same thing is valid for simulation based.
We can split this approach into several branches.
We can do simulation based verification using SystemVerilog language and UVM as the library, or we can use e language with eRM or UVM.
We can even use Python and there is an implementation of the UVM library in Python called pyuvm.
And there are many other approaches that we can take here.
But during this training, we will focus on this branch.
We will learn how to do pre silicon verification at module level, we will use a simulation based approach and as the language for developing that verification, we will use SystemVerilog and UVM as the library for doing verification.
Next, let's see exactly what it means to do verification on this branch.
Because we are doing pre silicon verification, it means that we need to work with the RTL code not with the physical chip.
And if we look at the block diagram, we will have to do verification for one single module out of this entire diagram.
We usually refer to the module that we need to verify as DUT.
DUT stands for Device Under Test.
There are small variation to this naming that you will encounter.
You will also see this abbreviation as Design Under Test or there is another abbreviation called DUV from Device Under Verification.
But essentially all refer to the module that you have to verify.
Our DUT will have some input interface and some output interface.
One of the first things that we need to do is to connect to the inputs and outputs of this DUT some components which will drive and monitor these interfaces.
Such a component is usually called an agent.
The role of the agent connected on the inputs is to generate traffic and send it to our DUT.
The DUT will take that input data and transform it based on its function.
And then it will send that information on the output interface.
On the outputs that information is picked up by our agent connected there.
So in our tests we will generate this random traffic that will stimulate continuously the interfaces of our DUT.
But we need to make sure that the outputs of the DUT are correct.
And for this we will need to build a component called model.
The job of this model is to take the same input as the DUT and apply the correct function on the input data.
So, if the DUT is working correctly, then the information outputted by the DUT will be the same as the information produced by our model.
And in order to compare these two data, we will have to create another component called the scoreboard.
The job of the scoreboard is to take the information from from the model and from the agent and compare them.
Our goal as verification engineers is to find scenarios in which for a particular input data, the function performed by the DUT is incorrect.
In this case, when the scoreboard gets the data and compares them, it will report it as a DUT error.
So, when we get such a scenario, we can say that we found the DUT bug and it will be the job of the design engineer to fix the RTL code.
All the components that we will build in order to do module level verification are usually wrapped in a class called environment.
So when you hear the term verification environment, it refers to this big class which is wrapping all the objects that we need in order to do verification.
In this training, you'll learn how to use the UVM library in order to build each component part of a verification environment.
That's it for this tutorial.
We had a brief overview on design verification and we discussed how module level simulation based approach works.
So in this training we will focus on module level verification, simulation based approach, we will use as programming language SystemVerilog and as library UVM.
Thanks for watching and see you in the next tutorial.
Bye!
