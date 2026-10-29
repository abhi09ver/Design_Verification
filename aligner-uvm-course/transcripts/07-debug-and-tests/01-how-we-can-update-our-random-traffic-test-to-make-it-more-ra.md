# How we can update our random traffic test to make it more random

*Chapter: Debug and tests · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we can update our random traffic test to make it more random.
To put things into perspective, this is the structure of the tests that we discussed in a previous tutorial and in this tutorial we are going to focus on this test.
A more accurate representation of the inheritance diagram is this one, in which we have in the middle between our uvm_test and our random test, this base test class in which we only declare the environment.
In our random test, we want to update the run_phase() in this way.
We want our test to run three individual steps.
In the first step, we want to write random values in all the configuration registers.
After that we want to generate random MD RX traffic and after that we want to read all the status registers.
From our random test we want to control the number of MD RX transactions that we are sending in this step.
And for this we can declare a field with which we will control the number of MD RX transactions.
We can declare this field as protected and then in the constructor we can initialize it to value 300.
Now let's focus on the implementation of the run_phase() task to see exactly how we can implement all these three steps.
We can implement each of these steps using virtual sequences.
So, for example, for the first step in which we want to write random values to the configuration registers, the implementation will look something like this.
We will have this virtual sequence for configuring the registers, and in here we create an instance of this virtual sequence, we randomize it, and then we start it on the virtual sequencer.
In the second step, in which we want to drive random MD RX traffic, we take a similar approach but this time we wrap the virtual sequence inside a repeat statement.
So we will use our number of MD RX transactions to control how many times we call this RX virtual sequence.
In this virtual sequence we will send only one random MD RX transaction.
So first we need to create an instance of this sequence.
Then we have to set the sequencer as the constraints in this virtual sequence will use information from the virtual sequencer.
Then we randomize it and send it to the sequencer.
And the last step for reading the status registers will look quite similar, so we will have this virtual sequence to read all the status registers.
We create an instance of it, we randomize it, and then we start it on the virtual sequencer.
Now let's see how we can implement these three virtual sequences.
First, our sequence for configuring the registers will have this inheritance tree, so we will extend this class from our base virtual sequence and then its body() task will look like this.
First, we need to get all the registers from the register block.
And after that, we need to keep in this registers queue all the configuration registers.
We can identify a register as being a configuration register based on its access rights.
So if the access right of that register is either read-write or write-only, we keep it.
Otherwise, we delete it from this queue.
Remember that we configured the access rights of each registers when we added the registers in the default map.
We configured the access rights with this argument.
So in our case, we will delete from this registers queue only the Status register, as this is the only register which is not writable.
So, at the end of this for loop, we will have in our registers queue three registers: Control, Interrupt Requests Enable, and Interrupt Requests.
Then we must shuffle this queue in order to access the registers in a random order, and then for each register in this queue, first we randomize the desired value and then we call the update() task which will trigger a write access on the APB interface.
We can take a similar approach with the virtual sequence for reading all the status registers.
Its body() task will look something like this.
This time we can identify a status register as a register which is read-only.
So, if we look on the code in which we declared these access rights, based on this condition, at the end of this for loop, we will have in our registers queue only one register, our Status register.
Even though at this point in our registers queue we only have one register, we can still leave this shuffle() call here as in the future our RTL might be updated and we can get other status registers in our default map.
And after we shuffle this queue, we go through each entry in this register queue and we read that register.
And now let's look on our last virtual sequence that we need to declare.
So, in this sequence, we have to send only one random MD RX transaction.
And to accomplish this, first, in our virtual sequence, we will have to declare a handler to an MD simple master sequence.
We must declare it with the rand attribute in front as we will randomize this virtual sequence.
Then in the constructor we create an instance of this sequence and in pre_randomize() we set the sequencer to point to the MD RX sequencer.
And once again we need to set the sequencer before we randomize this MD simple master sequence, as in the constraints of this sequence, we make use of fields which we access through the sequencer.
After we do this, we have to declare the body() task and the implementation is quite simple, we simply start this sequence on the MD RX sequencer.
And with that we went through all the three virtual sequences that we will use in our random test.
What I can already share with you is that this update that we will implement in our next tutorial is not enough to test all the features of our RTL.
For example, one thing that this test is missing is multiple resets.
So, for all the devices that we are verifying, we want to make sure that after we trigger a reset, the device will be able to recover correctly.
And there are at least two other features of our Aligner RTL which this test will not verify regardless of how many times we are running this test.
So try to think about this and see if you can identify what are the features that will never be tested by this code and in the next tutorial in our practice session I will share with you what are those features and why this test will never check those features.
That's it for this tutorial.
We talked about how we can update our random traffic test to make it more random.
For this we need to implement three virtual sequences.
In the first one, we will write random values in our configuration registers, with the second sequence we will send one random MD RX transaction, and with our last virtual sequence we will read all the status registers.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
