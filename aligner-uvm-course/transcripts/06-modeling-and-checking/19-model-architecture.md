# Model architecture

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about the Model architecture.
This is the current image of our verification environment and in this tutorial we are going to talk about the architecture of this component, the model.
And remember from the previous tutorial, the job of the model is to take the input data which goes into the RTL and generate the expected output data.
To figure out the architecture of our model component, we need to start from the block diagram of our Aligner RTL.
This is the picture showing the block diagram of our Aligner and it is taken from the Aligner specifications.
The input data on the RX side goes into this RX Controller, which determines if the access is legal or not.
So, this RX Controller is responsible for sending back the response on the RX interface.
If the access is legal, then that information is pushed into an RX FIFO and the data is popped from this RX FIFO by this Controller module, which is also responsible for doing the alignment.
Once the alignment is done, that aligned information is pushed into this TX FIFO.
And finally, the last module, this TX Controller, is responsible for taking the data out of this TX FIFO and put it on the TX MD interface.
So, we will try to mimic this architecture in our model of the Aligner RTL.
Our model will receive the data from our RX MD agent and we will process that information into some logic which will mimic this RX Controller module.
I put it like this in a cloud to represent that this logic will be implemented only using functions and tasks.
So this will not be a standalone class in our environment.
We will split this logic in order to handle separately the cases where the access is an illegal access or an OK access.
The job of this RX Controller logic is first of all to send to our scoreboard the expected response on the RX interface.
So this arrow is actually an UVM analysis port through which this logic will send its expected information.
Another role of this RX Controller logic is to update the register model, just like the RTL is doing, and this update is related to incrementation of that drop count register.
But once this RX Controller determines that the access is a legal one, then it will send that information to a model of an RX FIFO.
We will implement this RX FIFO with a class which is already implemented in our UVM library called uvm_tlm_fifo.
So the only effort on our side for this is to instantiate this class in our model.
Of course, based on the fill level of this RX FIFO, we will have to update our register model.
Remember that in our register model, we have several fields connected to this RX FIFO.
We have the RX_LVL from the Status register and then we have those interrupts like RX_FIFO_FULL and RX_FIFO_EMPTY.
Next, we will have to implement the logic from this Controller module and we will split this logic into several parts.
First, we will have some logic called Buffer Builder in which we will implement some tasks and functions to pop data from this RX FIFO and push it into this buffer.
The role of this buffer is to hold enough information which can be aligned by our alignment logic.
But once we have enough information to align it into this buffer, then we will have a logic to model the align logic.
So, we will have some tasks and functions which will take data from this buffer, will align that data, and that aligned data will be pushed into a model of the TX FIFO.
And just like before, we will model this TX FIFO using this uvm_tlm_fifo.
Once we reach the point where we will implement these models of our RX and TX FIFO, we will go into more detail about this class, this uvm_tlm_fifo, and we will discuss the API of this FIFO and we will see why this is helpful to us.
And just like in the case of our RX FIFO, we will have to use the information from the TX FIFO to update the status registers like TX_LVL, TX_FIFO_FULL and TX_FIFO_EMPTY.
And the last logic that we will have to model is the logic inside this TX Controller.
So to model this one, we will implement some logic called TX Controller.
Again, this will be a collection of tasks and functions.
And this logic from here will receive information from our TX agent and its role is to pop data from this TX FIFO and send it to the scoreboard.
And just like in this case, this arrow from here will be implemented using UVM analysis ports.
And don't worry if you find this diagram a little bit abstract, in the next tutorial we will reference this image when we will implement each part of our model.
So it will be much clearer for you in the next tutorial what it takes to implement this RX Controller logic or RX FIFO and so on.
But one important thing that I strongly recommend you to do is to be quite familiar with the Aligner datasheet, otherwise you might not understand some of the tutorials in which we will implement this model.
And for this I recommend you to go through the following chapters.
The first one is this one, "Flow Control" and in here you'll find some explanation about how all those modules from inside the Aligner are working.
So you'll find here description for the RX Controller, RX FIFO, Controller, TX FIFO and TX Controller.
The other chapter is this one "Interrupt requests".
And of course, this is also something that you'll have to do in a real project.
As a verification engineer, you have to have a very good understanding of the specification of the DUT that you have to verify.
That's it for this tutorial.
We discussed about the architecture of our model component and we looked through the relevant chapters from the Aligner documentation.
In the next tutorial, we will make the first step in implementing our model component.
Thanks for watching and see you in the next tutorial.
Bye!
