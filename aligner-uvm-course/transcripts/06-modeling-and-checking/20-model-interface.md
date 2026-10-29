# Model interface

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about the model interface.
This is the image of our model and in this tutorial we are going to talk about these arrows here.
So these are the input and output ports of our model.
So far, in our Model class we have two properties declared: the env_config and the reg_block.
And the next thing that we will add to our model class are the input ports.
So we will have one input port for receiving information from our MD RX agent and another input port for receiving information from our TX agent.
And because these are UVM analysis implementation ports, we will also need some write() functions associated with those.
And in order to implement these ports, our code will look like this.
First, we will have to declare the analysis implementation classes and then we will have to instantiate them.
And the information coming through these ports is the same information passed by the monitor inside our MD agents.
And finally, we'll have to declare the write() functions for the RX and for the TX.
Next, we will have to declare the output ports, the ports through which our model will pass the expected information to the scoreboard.
And the first output port that we have to declare is this one: port_out_rx.
So in order to pass information through this one, this needs to be declared as an UVM analysis port.
And the simplest information that we can pass through this one is this type: cfs_md_response.
This is the type for keeping the response inside the MD agent.
And it can have just two values: OK or error.
So we can pass this simple information through this port_out_rx.
The next port that we have to declare is this one on the TX side So this will be called port_out_tx.
Again it will be an UVM analysis port but this time the information passed through this port is this one cfs_md_item_mon because the expected information for us it will be the data, the size and the offset.
So we can put all this information in this cfs_md_item_mon.
Of course, this one also contains stuff like length or response, but these are irrelevant for us here.
And the last output port that we need to declare and that one is not represented here is the port through which we pass the information related to interrupt requests.
And because the interrupt request output signal from the DUT is a simple bit, we can also pass a bit information through this port.
And whenever we pass value 1 through this output port then our scoreboard knows that it will have to expect an interrupt request coming out of the DUT.
That's it for this short tutorial.
We talked about the interface of our model component and in particular the input and output ports and in the next tutorial we will implement these ports in the code.
Thanks for watching and see you in the next tutorial.
Bye!
