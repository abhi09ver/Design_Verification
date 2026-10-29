# Input and output ports of our Model class

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement together the input and output ports of our Model class.
The starting point is the EDA Playground project "Model Interface - Practice" which we need to copy.
And let's resize the windows.
The first thing that we have to do is to declare the UVM analysis implementation classes for receiving information from the RX and TX agents.
So let's do this.
That's it.
Now let's declare the handlers to our input ports.
That's it.
So the type of information coming through these ports is this one cfs_md_item_mon and this is the same class used by the output port from our monitor inside the MD agent.
Next, let's create instances of these ports in our constructor.
And finally, let's declare those write() functions.
That's it, so if everything is OK then we should see these messages printed in our log.
The last thing that we have to do for these input ports is to connect them and we can do this in the environment in the connect_phase() function here.
That's it.
Now let's give it a try and for this we don't need to open the EPWave after run and now let's click Save and Run to see if we get in the log the messages printed from our model.
Our simulation finished and let's scroll up to see the messages and we can see these messages "Model received information from the RX agent".
So everything looks good and now let's add the output ports in our model.
So let's go back to our model and up here the first thing that we have to do is to add the output port for sending to the scoreboard the expected information so the expected response on the RX interface.
So let's do this.
That's it.
So the type of information that we pass through this port is this one cfs_md_response.
And now let's create an instance of this port here.
And now let's do the same thing on the TX side.
But remember on the TX side the type of information that we want to pass is this one.
So let's do this.
So that's the handler and the passed information type is this one cfs_md_item_mon and now let's create an instance of this one.
That's it.
Now the last port that we have to declare is the one through which we passed the expected information for the interrupt requests and the type of information passed is bit.
So let's do this.
So that's the declaration and now let's create the instance.
That's it.
Now let's try to run our project and see if everything runs OK.
The simulation finished and if we look through the log we can see that we don't have any compilation issues.
So with that we managed to implement the interface of our model which is made out of these ports.
Two for the input and three for the output.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
