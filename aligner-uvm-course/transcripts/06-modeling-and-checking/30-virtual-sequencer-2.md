# Virtual sequencer

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement the virtual sequencer.
This means that in our environment we will declare the virtual sequencer class with all the references inside and also we will declare our base virtual sequence with the p_sequencer and then we will declare our slow pace virtual sequence.
The starting point is the EDA Playground project called "Virtual Sequencer - Practice", which we need to copy and now let's resize the windows.
Let's create the virtual sequencer class, so we will need to extend from uvm_sequencer and inside we have to declare the references to all the sequencers from our environment and also a reference to the model.
Let's create the file containing the virtual sequencer class.
Now let's include it in our Aligner package.
That's it.
And now let's declare the virtual sequencer class.
That's it.
So I added here the references that we need in the virtual sequencer.
Three of them are for the sequencers inside our environment and one for the model.
For the APB sequencer I used the uvm_sequencer_base class as we don't really need anything special from this sequencer.
And for the MD sequencers I used the base master and base slave classes from the MD package.
For the RX sequencer we don't really need anything special from this class so we could have used here the uvm_sequencer_base.
But for the TX sequencer we do need to access that pending_items FIFO which is declared in this class.
So for easy access in the virtual sequence we need to declare the correct type here.
Now let's create an instance of this virtual sequencer in our environment.
That's the handler and now in build_phase() let's create an instance of this.
That's the instance and now in connect_phase() let's connect those pointers.
That's it.
The only thing that we must pay attention to here is to do the correct casting for the MD sequencers, and this is because the sequencer from the MD agent it's actually declared in the UVM extension package.
Next, let's create our base virtual sequence class with the p_sequencer declared inside.
So first, let's declare the file.
And now let's include it in the Aligner package.
And now let's declare the class.
That's it.
I declared here the p_sequencer and I used as the type our virtual sequencer class.
Now let's declare the slow pace virtual sequence class.
Now let's include the file in the Aligner package.
And now let's declare the class.
So we have here our body() task with the fork-join and our fork has two branches, one for the RX transaction and the other for the TX transactions.
Now let's declare the code for the RX transaction branch, just like we discussed in the previous tutorial.
That's it.
So we have the constraints to drive the legal RX transaction and then the constraint to drive data size bigger or equal to the SIZE field from the Control register.
And now let's implement the TX transactions branch.
That's it.
So we have our do-while loop in which we are driving TX responses and we are driving an error response only for the last TX transaction.
Now let's use this virtual sequence in our random test to see how it drives the interfaces.
So in our random test we need to comment this response forever sequence.
And let's add our code in this repeat loop.
But first let's comment this part and we can add our code here.
That's it, so I'm creating an instance of our slow pace sequence, I'm setting the sequencer, I'm randomizing it, and then I'm starting the sequence on the virtual sequencer.
So let's do only one loop in this repeat to easily see what is happening on the waveforms.
Let's go to "Tools and Simulators" and enable "Open EPWave after run" and let's run our test.
The simulation finished and now let's add some signals on the waveforms.
So first let's add the MD RX interface.
And now let's add the TX interface.
And now let's add the SIZE field from the Control register.
And let's zoom a little bit here.
So in this run the SIZE field from the Control register was 1 and also on the MD RX interface we are driving with size 1.
So this means that only one transaction was outputted on the TX interface with the same data.
We can see these 3E from here oututted on the TX interface.
Let's try one more run to see if we get a seed in which the RTL has to output more than one TX transactions.
The simulation finished and in this run we have this interesting scenario in which the SIZE field from the Control register is 1 and our MD RX transaction was generated with size 4.
Let's zoom a little bit here.
This RX transaction is split into four TX transactions and we are driving an error response only for the last TX transaction.
So for this one here.
So that's exactly the scenario that we wanted to have in our virtual sequence.
Now let's update our test to run our virtual sequence 100 times and let's see how the waveforms will look like in this simulation.
The simulation finished and now let's quickly try to see if we are running correctly our scenario with the four requirements.
On the MD RX interface we are always driving a legal transaction.
You can see that the error response is zero.
Let's also add on the waveforms the RX level signal and let's zoom a little bit.
And you can see that the RX level only goes up to value 1 and then back to 0.
So we have that slow pace in which we are sending the RX transaction.
And on the TX interface, it looks like we are driving an error response only for the last transaction outputted.
So the SIZE field from the Control register is 1.
Here we are driving an RX transaction with size 2, so this one will be split into two TX transactions, this one and this one, and we are sending the error response only for the last one.
The next RX transaction has size 1, so there will be only one outputted TX transaction, this one from here.
And we are driving for this one an OK response.
The same scenario is for this one.
For the next RX transaction, the size is 4, so this one will be split into four TX transactions.
And we are driving an error response only for the last one.
The first three have an OK response.
So it looks like we managed to implement correctly the virtual sequencer and our slow pace virtual sequence.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
