# How we can model the illegal RX accesses

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we can model the illegal RX accesses.
And if we look at our model component diagram, we are going to implement this logic in this part, in the model of the RX Controller.
And illegal RX accesses means that we are going to implement this error part here in the scenarios in which the response on the RX interface is an error.
And just to clarify what exactly we need to implement here, let's look again at a short animation of the behavior of our Aligner in such a case.
So here we have the Aligner with its RX and TX interfaces, and up here we have the Status register and the Interrupt Requests register.
And for this particular scenario that we are talking about, we are interested in how this CNT_DROP register its incremented and this MAX_DROP interrupt request.
So initially our CNT_DROP register field is zero and whenever we are receiving an illegal access on the RX interface, when that access reaches the Aligner, the Aligner will increment this CNT_DROP.
And it will do this for all the illegal accesses it will receive.
So in this scenario, this CNT_DROP will be incremented to 2.
And let's say that we are receiving 254 of these illegal accesses.
Now at this point, if we are receiving a new illegal access, then our CNT_DROP will increment from 254 to 255, and this value is the maximum value we can represent on 8 bits, and this is the point where our MAX_DROP interrupt request will become 1.
And when this becomes 1, if the interrupt request is enabled in that Interrupt Requests Enable register, then we should also see our interrupt request output bit going to 1.
And one more important thing here, our CNT_DROP register will not change once it reached this maximum value of 255, regardless if it will receive new illegal accesses on the bus.
So this is a functionality that we will have to model in our model component and let's see exactly what functions we need in order to implement this behavior.
So first we will have to add in our model class a function called get_exp_response().
This function has as an input argument the information received from the RX monitor and its purpose is to return an expected MD response.
So in here we will determine if the access is legal or not.
Next, we will need a function called set_max_drop() which needs to set to 1 the MAX_DROP interrupt request.
The next function that we need will be called inc_cnt_drop() and the job of this function is to increment the mirrored value of this CNT_DROP.
And also here we need to pay attention that we should no longer change this CNT_DROP once it reach the maximum value.
So these are the new functions that we need to add in our model component in order to model this logic.
And we will call these functions in our write_in_rx() function, which is the function called whenever our RX monitor sends to the model new information detected on the RX MD bus.
That's it for this tutorial.
We talked about the new functions which are required for us to implement in order to model these illegal RX accesses.
In the next tutorial we will implement all this together in the code.
Thanks for watching and see you in the next tutorial.
Bye! i!
My name is Cristian Slav and in this tutorial we are going to talk about the scoreboard interface.
This is the image of our verification environment with all the components that we implemented so far and in this tutorial we are going to start working on the scoreboard.
So the first thing that we have to do is to declare the scoreboard component.
Our scoreboard class will extend from uvm_component and it will also implement this reset handler.
This means that we have to declare this handle_reset() in our class.
The next thing that we will have to declare is the port through which our scoreboard will receive from the model the expected RX information.
So because it is receiving information, this will be an analysis implementation port.
So we will declare this port_in_model_rx with its corresponding write() function and the type of information that we will receive through this port is this one cfs_md_response.
So this is the type of information that our model will send to the scoreboard, the expected RX response.
Next, we will declare the port for the expected information on the TX side.
So in the same manner, we will declare this port_in_model_tx with its corresponding write() function and the type of information coming on this port is this one: cfs_md_item_mon.
Next, we will declare this port for the interrupt request and in the same manner we will declare this port_in_model_irq with its corresponding write() function and the type of information coming through this port is bit.
So, through these ports we will receive the expected information from the model and now let's declare the ports through which we receive the information from the agents.
So, from the RX agent we will declare a port called port_in_agent_rx and the type of information coming through this port is this one cfs_md_item_mon.
The full information collected by the monitor inside the RX agent.
And the same thing will be on the TX side, so we will have to declare a port called port_in_agent_tx and of course through this port we will receive exactly the same type of information, cfs_md_item_mon, the type of information sent by the monitor inside the TX agent.
The last information that our scoreboard needs is the interrupt request outputted by the RTL, but for this one we don't have any monitor looking on this signal.
And this is because the output information interrupt request coming from the DUT does not require any special monitoring, it's just a simple wire which becomes one when the RTL outputs an interrupt request.
So this means that we can directly take that information in the scoreboard we don't need a port and for this we will declare in our scoreboard a pointer to the environment configuration class.
In this environment configuration class, we have our virtual interface in which we will add later the interrupt request signal.
And this is how we get the received information for the interrupt request in the scoreboard.
So that's all the API that we have to declare in the scoreboard in order to get the expected and received information that we need in the scoreboard.
That's it for this tutorial.
We talked about the interface that we need to declare in the scoreboard in order to get the expected and received information from outside.
In the next tutorial we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
