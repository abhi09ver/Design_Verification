# Tests organization

*Chapter: Debug and tests · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about tests organization.
In order to create a test with the UVM library, we simply have to create a class which extends from uvm_test.
With this simple rule, we can create as many tests as we want.
But having a big number of tests like this one is not something that we want.
This is because a lot of these tests will share some common code.
In most of these tests we will have the same logic to start the traffic on different interfaces of our DUT.
So that code will be repeated in all of these tests.
This means that any change in the way we start the sequences will have to be implemented in all or most of these tests.
A better way to organize the test is in the following way: From the uvm_test class we create one single test.
This one should be quite random in the sense that if we run it a sufficient number of times, it will cover all the scenarios that we need.
However, relying only on a big number of runs to cover all the scenarios that we are interested in is not a realistic scenario as this might take a really long time.
And for this reason, we can create other tests which inherit from our random test, but in this test we only apply constraints.
So, if we are interested in feature A of the DUT, then we want to run our random test but with the constraints which trigger feature A.
So this test to target feature A will make use of all the logic to start the traffic defined in our random test, and it will only contain constraints to enable this feature.
And we can create such tests for different features of the RTL.
And of course, based on the needs of the project, we can create even more directed tests out of these ones.
But the idea is quite simple, only have one random test which starts the traffic on the interfaces of your DUT and out of this one create different tests using inheritance and in these tests only apply constraints to your random traffic.
And let's go into more details to try to explain to you better what I mean by this approach.
In our random test for the Aligner RTL the traffic looks something like this.
We have some random traffic on the RX interface and based on the configuration from the Control register, the TX traffic will look something like this.
If we want, for example, to create a test which targets that drop counter feature, what we want to do is to apply constraints to this random test to only drive illegal traffic on the RX interface.
In this way, the drop counter will be incremented faster so we can test that interrupt associated with this counter.
So let's see how we can apply such constraints from our drop counter test.
First, we want to create a class in which to define the constraints for the illegal traffic.
And if we have in our random test a virtual sequence to start the RX traffic, then in our drop test, we simply create another class which extends from that virtual sequence and in here we define the constraint to generate only illegal MD accesses.
Once we have this sequence then we create our test which targets this drop counter feature.
This test, let's call it "random RX error", extends from our random test.
The only thing that we need to do in this test is in its constructor we need to specify that we want to override our RX virtual sequence with our new RX error virtual sequence.
And when we run this random error test, all the sequences are started from our test random with the only difference that the RX virtual sequence will be replaced by this RX error virtual sequence.
And in this RX error virtual sequence we defined the constraint to drive only illegal traffic.
And in this simple way we can create tests which will target different features of our RTL.
For example, if we want to test the RX and TX FIFOs, then we should constrain the traffic to look something like this.
On the RX interface, we want to drive as much data as we can, so we can constrain the size of all the MD accesses to have the biggest value possible, in our case 4 bytes.
So, this would push the maximum quantity of information in our RX and TX FIFOs.
And if we want these FIFOs to be filled fast, then we should limit the quantity of information outputted on the TX interface.
This means that we should set the minimum value in our SIZE field from the Control register.
So, our Aligner RTL will act like a bottleneck.
It will receive a lot of traffic on the RX interface, but on the TX interface will output one byte at a time.
As I told you, this type of test organization in which you have only one test here and then other tests which only apply constraints to this random test, it's an ideal scenario and in most of the projects you will not be able to have something like this.
But you can try to get as close as possible to this structure.
Let's see a possible test organization for our Aligner RTL.
From the uvm_test class, we can create two tests just like we have now.
One which targets the register accesses and one which targets random traffic on the RX and TX interfaces.
In these two tests, we have the logic to generate the necessary traffic.
And let's say that the register accesses are not working as expected and we want to help the design team to target different parts of this feature, and we can create tests which inherit from this register access test but are targeting different parts.
We can have a test in which we only target unmapped addresses, and we can have another test which is only doing read accesses, and from our random test we might want to have tests which target different features, and we might need to create tests which are targeting the drop counter and the FIFOs just like we discussed in previous slides.
We can go one step further and from our FIFOs test we can create two other tests, one in which we set the SIZE of the Control's field to the minimum value and one in which we set the maximum value for that register field.
There are two main reasons for which you want to create different tests in which you apply more and more constraints.
First, you might need to create such tests in order to hit the coverage that you need faster.
For example, this test which is targeting the drop counter will help you test the drop counter feature much faster than this random test.
The other reason for creating such tests is to help the design team investigate a particular part of the RTL much faster.
They might be at a stage in which they are developing the logic for unmapped accesses, and having a test which is targeting that particular part of the RTL will help them develop and debug that feature much faster.
In the next tutorials of this section, we will not implement all these tests.
We will only focus on these ones.
We will update the register access test and our random test to truly drive random traffic and then we will create this random errors error test to target the drop counter feature.
Once you learn how to create this test only by applying constraints then it will be easy for you to implement on your own the rest of the tests.
That's it for this tutorial.
We talked about how to organize our tests in this tree-like structure using inheritance.
Thanks for watching and see you in the next tutorial.
Bye!
