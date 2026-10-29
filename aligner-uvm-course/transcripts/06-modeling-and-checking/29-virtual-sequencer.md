# Virtual sequencer

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about the virtual sequencer.
This is the current image of our verification environment and in this tutorial we are going to talk about this last component in our environment, the virtual sequencer.
The definition of a virtual sequencer is this one: A virtual sequencer is a sequencer that is not attached to a driver and does not process items itself.
To create a virtual sequencer class, we simply have to extend from uvm_sequencer.
So, in our case, we will define this virtual sequencer class which extends from uvm_sequencer.
Notice that in the case of the virtual sequencer, we are not specifying here as a parameter the type of the item for the uvm_sequencer.
Inside this virtual sequencer class, we need to define references to all the sequencers in our environment.
In our case, we have 3 sequencers: APB, MD RX and MD TX.
Having these references inside the virtual sequencer is something that the UVM documentation recommends.
And beside this, we will also need in our virtual sequencer a reference to the model.
So that's all the things that we need to declare in order to have our virtual sequencer.
The advantage of having a virtual sequencer in the environment is that you can use virtual sequences.
The virtual sequencer and the virtual sequences represent a mechanism through which we can control the sequences from all the agents in our environment.
To declare a virtual sequence it's pretty easy.
A virtual sequence is nothing more than a sequence associated with a virtual sequencer.
This means that we can simply create a class which extends from uvm_sequence.
But to iterate, the main idea with these virtual sequences is this one: With virtual sequences we can coordinate stimulus generation across multiple interfaces.
This means that from a virtual sequence we can start sequences which will be executed by the agents inside our environment.
This will allow us to create scenarios which we can easily reuse later.
So, we can have a scenario packed in such a virtual sequence and we can reuse that sequence throughout our tests or even at system level for example.
Of course, this will imply that at system level we will also be able to drive those interfaces.
To start a sequence from a virtual sequence, we have several options.
We can either use directly the API of the sequence class, but we also have access to two macros.
One is this `uvm_do_on and the other this `uvm_do_on_with.
And let's look at the arguments of this `uvm_do_on macro.
The first one is the sequence or the item that we want to start and the second one is the sequencer on which we want to start that sequence.
So, this is how we will specify from a virtual sequence on which sequencer we want to start a particular sequence.
The other macro `uvm_do_on_with will allow us to also add constraints to the sequence that we want to start.
And we can do this using the third argument of this macro.
We will use this macro in our next tutorial where we will implement such a virtual sequence and you will see exactly how this one can be used.
Now let's define a scenario that we want to run in our test and we will see how we can implement that scenario with virtual sequences.
Our scenario will have four requirements.
The first one is this: We must send a legal MD RX transaction.
Once we send this RX transaction, we must wait until it is completely outputted on the TX interface.
Here we must be careful because an RX transaction is only completely outputted on the TX interface only if its size is greater or equal to the SIZE field from the Control register.
So, for example, if the SIZE field is equal to 4 and we send an RX transaction with size 1, that transaction will be stuck in the intermediate buffer because the Aligner will wait to have at least 4 bytes in order to align them.
So, this is why in this scenario we must be careful to always send RX transactions with the size greater or equal to the SIZE field.
The next two requirements are referring to the response on the TX interface.
If the MD RX size is equal to the SIZE field on the Control register then we must respond with an OK response on the TX interface.
This is the scenario on which for one incoming RX transaction we have only one outputted TX transaction.
But we also have the possibility to send an RX transaction with the size greater than the SIZE field.
This means that for one incoming RX transaction, the Aligner will send multiple TX transactions.
And the requirement is that we will have to respond with an error response only for the last TX transaction.
So let's imagine that the SIZE field is equal to 1 and we send an RX transaction with size 4.
This means that on the TX side, the Aligner will send 4 transactions.
For the first three, we will have to send an OK response and we will have to respond with error only for the last TX transaction.
And now let's see how we can implement such scenario with virtual sequences.
The first thing that we will have to do is to create a base virtual sequence class in which we define this p_sequencer using this macro `uvm_declare_p_sequencer.
Remember that with this macro we will define a field inside our sequence called p_sequencer which will be of this type.
Through this p_sequencer we will have easy access to all the references to the sequencers that we defined in the virtual sequencer.
Once we have this base class then we can define our virtual sequence.
I called this virtual sequence "slow pace" as we will have to send one RX item and then wait until it is completely outputted from the RTL.
So we will send RX items at a slow pace.
Inside our virtual sequence we only have to define the body() task.
In our sequence we will have to send RX and TX transactions.
So this means that inside the body() task we will have to define a fork-join with two branches, one for sending the RX transaction and on the other we will send our TX transactions.
So, let's discuss the implementation of these two branches and first let's focus on this RX transaction branch.
The first thing that we will have to do is to declare a handler to our RX sequence.
The type of our RX sequence will be this simple master sequence from our MD package.
As we discussed earlier, in order to start this sequence, we will use this macro `uvm_do_on_with.
The first argument is our sequence.
The second argument is the sequencer, so in this case is the MD RX sequencer, and in the third argument we will add the constraints based on the first two requirements.
In order to send a legal MD RX transaction, remember that in the Aligner specification we have these two rules.
So we can add the constraints based on these two formulas.
We can get the Aligner data width from the environment configuration object, and this is the point where we make use of the model reference from our virtual sequencer.
Once we have the Aligner data width, we can implement these two constraints to reflect these two formulas.
So for the offset we can use item.offset and for the size we can use item.data.size().
The second requirement specify that the MD RX size must be greater or equal to the SIZE field from the Control register.
This is an easy constraint to implement.
First, we must define this ctrl_size field which we allocate to the value of the SIZE field from the Control register.
And then we can simply constrain item.data.size() to be greater or equal to this ctrl_size.
So this is how we send the RX transaction and now let's see how we can send our TX transactions.
Remember that on the TX side, we have to send the response for one or many TX transactions.
The number of the TX transactions depends on the size of the RX transaction and the value of the SIZE field from the Control register.
So because of this, in the TX transactions branch, we have to define two fields.
The first one, tx_item_idx, represents the index of the current TX item for which we send a response.
The second one represents the total number of TX transactions for which we have to send a response.
With these two fields, we can create a do-while loop.
In our loop, we will send TX responses as long as the TX item index is smaller than the number of TX items.
And this index we increment as the last thing in our loop.
To send responses on the TX interface we must define this TX sequence which is of this type: simple slave sequence.
To start this sequence we will use the same macro `uvm_do_on_with.
And just like before, we will use for the first argument our sequence.
For the second argument we will pass the reference to the MD TX sequencer and in the third argument we will add the constraints.
Remember that we had a special mechanism for our MD TX driver.
We had to wait for the monitor to tell us that there is a TX item started.
And to get this information we had in the sequencer this pending_items FIFO.
So, to correctly synchronize with the bus, before we send a TX response, we must get the current item from the monitor from this FIFO.
After we get this item, we can be sure that the MD RX transaction already started.
So at this point we can calculate the number of TX items that we need to send.
And to get this number it's pretty easy we simply have to divide the size of the RX item with the SIZE field from the Control register.
Now the only remaining thing is to add the constraints which will reflect these last two requirements.
So for this one if the MD RX size is equal to the SIZE field from the Control register then respond with an OK response.
The constraint looks like this.
When RX size is equal to the SIZE field then our number of TX items will be equal to 1.
So this means that we will have to constrain the response from the item with value OK.
For the last requirement we will be in the scenario in which the number of TX items is greater than 1 and we can split this in two.
If the index of the current TX item is smaller than the total number of TX items, then we send an OK response and we identify the last TX item with this condition here.
And for this one, we send an error response.
So these last two constraints represents the implementation of this last requirement.
And that's the entire code for the TX transactions branch.
So that's our entire virtual sequence and to start it we simply call the start() task passing the virtual sequencer as a reference.
You can find more information about this subject in the UVM documentation.
So first of all in the User Guide you have this section under "Using Verification Components", there is this "Virtual Sequences" and in here you can read more about virtual sequences and also the virtual sequencer.
And also in the Class Reference Manual you can read more about the macros used to start the sequences so if you go here in "Macros and Defines" under "Sequence and Do Action" you can read more about these `uvm_do_on and `uvm_do_do_on_with.
That's it for this tutorial.
We talked about what is a virtual sequencer and what is a virtual sequence.
We talked about how we can build a virtual sequence which controls the RX and TX interfaces.
And finally we discussed where you can find more information about this subject.
In the next tutorial we will implement the virtual sequencer and that "slow pace" virtual sequence in our environment.
Thanks for watching and see you in the next tutorial.
Bye!
