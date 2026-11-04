# How we can build a custom register predictor

*Chapter: Register model (RAL) · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to talk about how we can build a custom register predictor.
In the previous tutorial we managed to create an instance of this predictor and we used for this one that class from the UVM library called uvm_reg_predictor and we connected this predictor to the register model and to the monitor from the APB agent.
We saw that this connection works correctly at least for accesses with no error.
In that case, for example, if we have here a write access, that write data will be used to update the registers inside the Aligner and also inside our register model.
However, for accesses with an error response, there is a problem with this implementation of the predictor because in that case, the predictor still sends the information to the register model while the RTL rejects it and it will not update the register values.
And we can easily fix this problem by making use of the API of this class uvm_reg_predictor.
We know that this predictor receives the information from the monitor via this bus_in analysis port.
And if we look on the implementation of this uvm_reg_predictor class, we can see the declaration of this bus_in field.
This one is nothing more than a simple UVM analysis implementation port.
So this means that there is also a write() function inside our uvm_reg_predictor, this one.
And because this one is public and virtual we can actually create an extension of this uvm_reg_predictor and we will call this class cfs_algn_reg_predictor and in this write() function from our class we can call the write() function from the parent only for accesses with no errors.
And the code will look something like this.
In this write() function we can use that bus2reg() function from the adapter to transform the information coming from the monitor to this generic uvm_reg_bus_op.
This will give us access to this status field, and we will call the parent implementation of this write() function, via this super.write(), only if the status is OK.
And in this way, the registers from our register model will not be updated for accesses for which the RTL return an error response.
However, this operation.status is the information returned by the RTL and we cannot rely that the RTL will return the correct response every time.
And because of this we must implement a logic which will check if this operation.status is the correct one, either OK or NOT_OK.
And in order to verify that the response from the RTL is the correct one, we must look in the Aligner documentation and see what are the scenarios in which the RTL should respond with an error.
We can easily find this in the Aligner documentation: if we jump to this "Registers" section, we have these rules which describe when the Aligner must respond with an APB error.
So these scenarios are the following: when we try to access a location on which no register is mapped.
When we try to write to a full read-only register or when we try to read from a full write-only register or when we are doing an illegal write access to the Control register.
And to understand what an illegal write access to the Control register is, we must look in the "Control Register" chapter.
And in here we have the following statements.
The first one is this: Trying to write value 0 in this field, in this SIZE field, will return an APB error.
So this is our first error scenario for writing to the Control register.
And the second one is this one: Trying to write an illegal combination of SIZE and OFFSET.
And this illegal combination of SIZE and OFFSET has to do with the MD protocol and we can find the definition written here in this "RX Controller" via this formula.
Aligner data width plus OFFSET modulo SIZE must be equal to zero.
I put on this slide the error scenarios from the Aligner datasheet just to get a better feeling of what we need when we will implement this.
The first thing that we will need is a function which will return the expected response for a particular access.
And we will create in our cfs_algn_reg_predictor a function called get_exp_response() which will return the expected response for a particular access based on these error scenarios.
In order to determine if we are in the first error scenario, any access to a location on which no register is mapped, we will use a function from the uvm_reg_map class called get_reg_by_offset().
We will provide as an input argument for this function the address of the access and this function will return a pointer to the register mapped on that address or a null pointer if there is no register mapped to that location.
For the next two error scenarios, any write access to a full read-only register or any read access from a full write-only register, we will use another function from the uvm_reg_map called get_reg_map_info().
This function returns a class and there is a field in that class which will tell us if a register is read-only or write-only.
For the last error scenario, illegal write access to the Control register, we need to determine what values will be written in SIZE and OFFSET fields based on the data on the APB bus.
And for this we will implement a function in our predictor called get_reg_field_value() in which we will extract this information.
To figure out if this formula will be equal to zero or not, we also need in our predictor this "aligner data width" information.
This information is only available at the environment level.
And to pass it to our predictor, we will place this information in an environment configuration component and in the predictor we will create a pointer to that environment configuration instance.
And as long as we implement that environment configuration component, we can also place there a switch to to enable or not this check on the response from the RTL and we will call that field has_checks.
So this means that in our environment we will create this environment configuration class and in here we will declare two fields has_checks and algn_data_width.
These will be private, or local, and we will create getters and setters for these two.
And our predictor will have a pointer to this environment configuration in order to access this information.
That's it for this tutorial.
We talked about how we can extend the UVM register predictor class and we also talked about how we can verify the DUT response for the register accesses.
In the next tutorial, we will implement all this together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
