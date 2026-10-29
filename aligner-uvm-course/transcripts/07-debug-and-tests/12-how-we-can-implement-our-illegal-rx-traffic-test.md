# How we can implement our illegal RX traffic test

*Chapter: Debug and tests · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we can implement our illegal RX traffic test.
This is the structure of the tests that we discussed in a previous tutorial and in this tutorial we are going to focus on this test from here.
Our goal for this tutorial is to create a test which extends from our random test and in this new test we should drive only illegal RX accesses.
And we can accomplish this just via constraints.
So let's see how we can implement this.
In our random test, the sequence which is driving MD RX transactions is this one.
So what we need to do is to first create a child class from this one.
From this new virtual sequence we only want to generate illegal RX traffic.
And as I told you, we can do this only via constraints.
This means that we need to add here a constraint to generate only illegal RX traffic.
In order to write this constraint, we need to have here the information about the Aligner data width.
So we need to declare this field here and in pre_randomize() function, we can allocate its value in this manner.
Once we have this information, we can add the constraint which will look like this.
With this constraint, we are specifying that an illegal access is defined by one of these two conditions.
The first condition is saying that the data width plus the offset modulo data size must be different than zero.
The second condition for defining an illegal access is this one: data size plus the offset must be greater than the Aligner data width.
Once we have this virtual sequence, then we can declare our test class.
As we discussed, our illegal RX traffic test must inherit from our random test.
In the constructor of our new test, we need to do two things.
First, we need to set this number of MD RX transactions to value 300.
This will help us to verify the scenarios in which the drop counter will reach its maximum value.
Remember that the drop counter can go all the way up to 255, so driving 300 MD RX transactions is more than enough to make that counter reach its maximum value.
The last thing that we need to do in our test is to override our RX virtual sequence with our new RX error virtual sequence.
And this is everything that we need to do in our new test.
That's it for this tutorial.
We discussed how we can implement our illegal RX traffic test and to accomplish this we need to create a virtual sequence in which we constrain the MD RX transaction to only generate illegal RX traffic.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
