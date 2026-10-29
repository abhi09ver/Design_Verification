# Our discussion about the UVM register model

*Chapter: Register model (RAL) · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to start our discussion about the UVM register model.
As the name suggests, the UVM register model helps you model the registers of a DUT.
And in the case of the Aligner, we have four registers: Control, Status, Interrupt Requests Enable and Interrupt Requests.
And in this section, we will model these four registers using the UVM register model.
And let's take a look at our environment and see where exactly we will implement this register model.
So these are the instances which will contain this register model.
Inside this register model instance, which will stay inside this model component, we will have the actual model of the registers.
Then we will need this predictor component which will make the connection between the APB agent and the register model.
So basically it will translate the information coming from the APB agent to something that the register model can understand and work with.
And one other job of this predictor is to check that the response for each APB transaction is the expected one.
So in here we will implement the rules for expecting an OK or an ERROR response on the APB interface.
And finally, we will also implement some fields in this Environment Configuration component as we need to pass some information to this predictor.
Now let's redraw this image of the environment by removing the MD agents and all other components here, just to simplify things a little bit.
So in here I kept the APB agent, the predictor, and the register model just to understand a little bit easier what will happen in our environment once we implement this register model.
In the register model, we will have the actual model of our four registers.
And whenever the driving part of our agent will send some information on the bus and let's say for example, that we want to send a write access to address 0.
So address 0 is the address of the Control register.
And with this data 101, this means that we want to write with value 1 the OFFSET field and the SIZE field.
So once we send this information on the bus, it will reach the DUT and then it will be picked up by the monitor.
And in the monitor information, we will also have the response.
The information from the monitor will be sent to the predictor.
And here the predictor will determine if the response is the expected one or not.
And, if the response is OK, then this information will be sent to the register model which will update the values of the register fields correspondingly.
So in this example the OFFSET and the SIZE will be updated with value 1.
So for write accesses the job of the register model is to update the values of our register model.
But we also have read accesses.
And for this scenario, on the driver side, the same thing will happen.
The information will be sent to the DUT and it will be picked up by our monitor.
And in this case we will have in the read information, the data and the response.
Then from the monitor the information will be sent to the predictor which will again check the response if it is the expected one or not.
And, if the response is OK, then this information will be sent to the register model.
And in the read case, the job of the register model is to compare the data returned by the RTL with the data that's inside the model.
And in this particular scenario, there is a mismatch for this field and the register model will automatically trigger an error letting us know that there is a possible issue with our DUT.
One other benefit when we implement the registers using the UVM register model is that our test can be a little bit more abstract in the sense that we no longer have to use the APB sequences in order to send traffic on this APB interface, but we can actually use API part of this register model.
So each register will have some tasks for doing writes and reads and we can change our test to look like this.
For example, if you want to write to the Control register, we can call this write() task with the value that we want to write and this will trigger an APB access with the correct parameters in order to write this information in the Control register.
But for this approach we still have to know the exact position of these fields: SIZE and OFFSET, in order to fill this data value here.
And there is another option to write this Control register.
For example, we can call this API so we can set the value of the OFFSET that we want to write, the value of the SIZE, and then we simply call the update() task.
And this will again trigger the same APB access in order to write these values inside our register.
And, as we have some API to write to some register, we also have the API to read the register.
So we will have this read() task which will read the value of some register.
And in this way, our test will no longer have to call some APB sequences to access the registers, but it will be this abstract implementation.
And if at some point in the future this interface will be changed to something else, let's say I2C or AHB or something else, then we simply change the agent here, but our test will remain the same.
All this functionality of updating the registers during write accesses, of checking the register during read accesses and also having this API for our tests is implemented using some base classes defined in the UVM register layer.
And let's quickly go through the most important classes part of this UVM register layer to get familiarized with their names and what they are used for.
The first class is this uvm_reg_field and this class is used to model a register field.
So in our case, if we look at the Control register, we will use this class to model these three fields.
The next class is the uvm_reg, so this one is used to model an entire register.
So an uvm_reg is a container of one or many uvm_reg_field(s).
And if normally we actually use the uvm_reg_field as it is, so we don't extend this class to define something custom, in most of the times, for the uvm_reg, we actually extend this class in order to define inside it all the fields part of a register.
And we can see this also from a class collaboration diagram.
So we have this uvm_reg class which we usually extend to create a custom register class, let's call it my_reg.
And in this custom class we can have any number of register fields instantiated under it.
So this is how we should read this collaboration diagram.
Inside my_reg we can have any number of uvm_reg_field(s).
The next class is uvm_mem and this one is used to model a memory.
And, just like the register field, normally we use this uvm_mem class directly without any extensions.
But in our case for the Aligner we will not use this uvm_mem as we don't have any memory inside our Aligner.
The next class part of the UVM register layer is called uvm_reg_file.
This register file is a container for other registers, and we normally use this register file when we have a group of registers which is repeated inside a DUT.
So for example, if we have register A, B and C, and then we have A, B, C (1), A, B, C (2) and so on, we put that group inside the register file and then we instantiate that register file as many times as we need.
But in the Aligner case, we don't have such group of registers, so we will not use this register file.
And let's look at the class collaboration diagram.
For this uvm_reg_file we normally extend this class to create a custom reg file.
And this reg file can contain any number of registers, but it also can contain any number of other register files.
So you can create a very complex structure of register file inside the register file inside the register file and so on.
The next class in the UVM register layer is the uvm_reg_block.
And this register block is the container for all the registers.
And in our case, we will wrap all these four registers inside an UVM register block.
And an instance of a register block is called a register model.
And now let's take a look at the class collaboration diagram to see how this reg block is used.
Normally, you create a subclass of this register block in which you can put any number of UVM registers, any number of register files or any number of memories.
But you can also put any number of other register blocks.
So just like for the register file, you can have a very complex structure of register blocks in which you have one instantiated in another and so on.
And usually you see this complex structure at system level verification, where you create a big register block which you will build using the register blocks defined at each module level verification for each module part of the entire system.
And the last class that I want to mention is this uvm_reg_map and this register map is the class which contains the information about the address at which a register is mapped when it is accessed via an interface.
This register map, you normally use it as it is.
You don't really have to extend this register map in normal scenarios.
And you can have any number of these register maps under a register block, because you can have scenarios in which the registers can be accessed not through one interface like we have in our case.
So for the Aligner, we can access the registers only via the APB interface.
You can have scenarios in which you have, for example, two or three interfaces through which you can access the registers inside the DUT.
And in such scenarios you can have the registers map to different addresses based on the interface through which you access those registers.
And for such scenarios you will have one instance of this register map for each physical interface that you will have in the DUT.
So these are the main classes part of the UVM register layer and we will discuss them in details once we will use them in our environment.
You can also find information about these classes in the UVM documentation.
In the "Class Reference" manual, under the chapter "Register Layer", you will find the information that you need about these classes.
And also here you can see the collaboration diagram that we also discussed in our presentation.
And in the "UVM User Guide" you also have a dedicated chapter, this one, "5.
Using the Register Layer Classes" and in here you can find information about these classes and how to use them in your environment.
That's it for this tutorial, we discussed about what is a register model and what are its features.
And we also discussed about the UVM register layer classes which we will use in order to build our register model.
And finally, I showed you where you can find more information about these classes.
In the next tutorials part of this section, we will build this register model for our Aligner DUT.
Thanks for watching and see you in the next tutorial.
Bye!
