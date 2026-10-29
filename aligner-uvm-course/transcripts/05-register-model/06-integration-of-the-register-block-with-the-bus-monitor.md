# Integration of the register block with the bus monitor

*Chapter: Register model (RAL) · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to talk about the integration of the register block with the bus monitor.
So far we managed to implement the register block and instantiate it in our environment, but this register block does nothing at the moment because we did not connect it to our APB agent.
And in this tutorial we will learn how to connect this register model to the monitor from the APB agent.
We can achieve this connectivity via a component called Predictor.
This predictor is implemented with the help of a class from the UVM package called uvm_reg_predictor.
This class has a parameter called BUSTYPE and we should pass to this BUSTYPE parameter the type of the class sent by the monitor, in our case that cfs_apb_item_mon.
The actual connection between the monitor and the predictor is done via analysis ports.
Our monitor has that output_port and we should connect that output_port to an analysis implementation port from the uvm_reg_predictor.
And that analysis implementation port is called bus_in.
And let's see a short animation to understand better how the information travels from the interface to the monitor, to the predictor, and then to the register model.
When there is an APB access, that access is collected by the monitor and because its output_port is connected to this bus_in from the predictor, this information will reach the predictor.
But at this point, the type of this information is this one, cfs_apb_item_mon, and the predictor does not know how to interpret the information from this class, so it needs to translate it to something that it understands.
And this translation is done with the help of an adapter.
The uvm_reg_predictor has this public field called adapter which we need to allocate to something and the type of this adapter field is this one, uvm_reg_adapter.
This is a class part of the UVM package and this one is a virtual class so in order to use it we need to create a child of this class and implement any pure virtual functions.
This uvm_reg_adapter has two important virtual functions that we need to be aware of.
One is this bus2reg(), and this function will hold the information on how to transform this cfs_apb_item_mon to whatever the predictor understands, and the other one is reg2bus().
This one is used to do the reverse transformation from something that the predictor works with to something that the APB agent can understand and, in particular, the sequencer.
So this reg2bus() is used when we will connect the register model to the sequencer of the APB agent, but currently we will focus only on this bus2reg().
As I told you, this uvm_reg_adapter is a virtual class, so we need to create a child class and we will call this cfs_apb_reg_adapter.
And in this cfs_apb_reg_adapter, we will implement these two pure virtual functions from here.
So in this bus2reg(), we will transform this class cfs_apb_item_mon to something that the predictor can understand, and that something is this one: uvm_reg_bus_op.
This is not a class, it's a struct and of course it also comes with the UVM package.
So in this bus2reg() we basically have to copy the information from cfs_apb_item_mon to information from uvm_reg_bus_op.
And let's see the fields that we need to assign in this struct.
The first one is kind, which holds the information if the access is a read or a write.
Then we have address, data, and status.
And this status holds the information if the access was with error or not.
So the predictor will use its adapter pointer to call this bus2reg(), which will transform this cfs_apb_item_mon to uvm_reg_bus_op.
So, at this point, the predictor can interpret this information and it needs to send this information to the register model.
And the connection between the predictor and the register model is done via a pointer to the address map.
And this pointer is called map.
So, we need to connect this map pointer from the uvm_reg_predictor to that default_map field from the register model.
So via this map, the predictor will send the information to the register model.
If that information is a write access, then the registers will be updated.
If that information is a read access, then the returned data by the RTL will be compared with the mirrored value.
So, this is how we integrate the register model with the bus monitor.
So, in the next tutorial, we will implement all this together, but besides doing this connectivity between the register model and the monitor, we also need to implement the logic to reset the register model, and this is a good time to look again on the API of the uvm_reg_block.
And beside the functions that we already talked about in the previous tutorial, in the uvm_reg_block there is another function called reset().
And when we call this reset() from the register block, of course all the registers inside the register block will be reset.
The logic to reset the register model will be quite similar to what we implemented in the agents.
Our environment and model classes will implement that interface UVM extension reset handler and the environment in its handle_reset() function will call the handle_reset() function of the model and this one will call the reset() function of the register model.
So you will see in the next tutorial when we will implement this that the logic is quite simple.
And as always let's also look in the UVM documentation to see where you can find more information about this.
In the "UVM Class Reference" manual there are several sections under the "Register Layer", "DUT Integration" you have these three chapters.
The first one this "Register Model Adapter" where you can find the API description of this uvm_reg_adapter.
You can see here that the class it's virtual and it has these two functions reg2bus() and bus2reg().
Another important chapter is this one "Explicit Register Predictor" where you will find the description of the uvm_reg_predictor class.
And finally you'll have this "Generic Register Operation Descriptors" and if you scroll down here you'll find this uvm_reg_bus_op struct.
Let's also look in the "UVM User Guide" to see where you can find more information about this subject.
So you can go to the "Using the Register Layer Classes", "Integrating a Register Model", there are two important chapters here.
The first one, this "Transaction Adapter", in here you can find information about how you should use this uvm_reg_adapter.
And one important statement that I want to show you in this chapter is this one.
Because this transaction adapter is specific to the bus agent, not the register model, it should be provided as part of a UVM-compliant bus UVC.
This means that in the next tutorial when we will implement that cfs_apb_reg_dapter, we will include that class in the APB package because of this statement here.
So this is one thing to keep in mind for the next tutorial.
And the other important chapter is this one: "Integrating a Register Model with a Bus Monitor".
And you'll find here also the information that we talked about in this tutorial.
That's it for this tutorial.
We talked about how to integrate a register model with a bus monitor and for this we had to go through some of the API of the UVM Register Predictor class, UVM Register Adapter class, and also that UVM Generic Bus Transaction struct.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
