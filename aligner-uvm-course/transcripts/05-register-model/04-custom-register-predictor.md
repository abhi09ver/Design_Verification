# Custom Register Predictor

*Chapter: Register model (RAL) · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to code together the Custom Register Predictor.
The starting point is the "Custom Register Predictor - Practice" project from EDA Playground which we need to copy.
And now let's resize the windows.
So, let's go again through the problem that we are trying to solve in this tutorial.
If you remember from the previous tutorials when we did a write access to the Control register, here we tried to write the SIZE field from Control with value 0 which is illegal, the RTL returned an error.
However, our predictor still sent that access to the register block which updated the value of the SIZE field with value 0.
And this is not something that we want.
And we discussed in the previous tutorial that the solution for this problem is to implement a custom register predictor which will filter all the accesses with error from being sent to the register block.
So let's create this custom register predictor.
First we have to create the file.
And let's include this file in our Aligner package.
Now let's go back to our file and define our predictor class.
So we created this cfs_algn_reg_predictor class which extends from this uvm_reg_predictor and we should still keep this type, this BUSTYPE, in order to keep our predictor as generic as possible.
And I simply pass this new BUSTYPE parameter of our new class to the BUSTYPE parameter of this uvm_reg_predictor.
Now only with this let's replace the type of our predictor from this one to this one.
And we should do this in the environment at the declaration and where we instantiated the predictor here.
And now if we run we should get the same error that we got in the previous tutorial.
So let's give it a try.
The simulation finished and let's look on the log.
And we still get the same error saying that there was a mismatch when we read the Control register.
RTL returned correctly the reset value, which is this 1 for the SIZE.
But we have in the mirrored value field value 0x200, because our predictor still sends to the register block this write access with error.
So let's filter this write access.
To filter out those accesses with error we need to overwrite the write() function.
So this write() function is called whenever our APB monitor collects some information from the APB bus.
So in this "tr" argument here we are getting whatever information the monitor is sending.
But as we don't know here its type we need to cast it to that uvm_reg_bus_op.
So let's do this.
And for this casting we are simply using this bus2reg() function from our adapter.
Now let's send to our register block only the accesses with an OK response.
And that's it.
Now let's give it a try to see if our code is working so we should not get any error when we are running right now.
The simulation finished and let's look through the log.
We don't get any UVM errors and if we look on the messages printed from the predictor we are only seeing this one which is related to that observed read.
So it looks like our update work.
We are not getting any messages from the predictor for this error transaction from here.
But remember that this operation.status is the response of the APB access returned by the RTL, but we do not know if the RTL will respond properly to all the accesses on the APB bus, so we need to verify this status information before using it in our code.
And as we discussed in the previous tutorial, we will implement a check here.
But before doing that, let's declare our environment configuration component as we will need fields from that component.
So let's first create the file.
And let's include this file in our Aligner package.
Now let's declare the environment configuration component.
Now let's declare in here the two fields that we talked about: has_checks and algn_data_width.
Let's assign some default values for these fields in the constructor.
Now let's declare the getters and the setters.
That's it.
And what we can do is to add some extra checks for the value of this aligner data width.
Remember from the Aligner specifications that we have some restrictions for this one.
Its minimum value must be 8 and it should also be a power of 2.
So let's implement such checks here.
That's it.
Now let's declare this environment configuration in our environment class.
And now let's create an instance of this environment configuration in our build_phase(). environment configuration in our build_phase().
That's it, and let's configure those two fields: has_checks and algn_data_width.
That's it, so we are passing to this algn_data_width from the environment configuration the value of this parameter ALGN_DATA_WIDTH.
Now what we can do is to add a pointer to this environment configuration class in our predictor.
And in the environment in the connect_phase() we can connect this pointer.
That's it.
Now let's go back to our predictor and in here we must implement the function get_exp_response() which will give us the expected response for each access on the ABP interface.
So let's do this.
So the return type of this function is this uvm_status_e, which is the type of this field as we will have to compare operation.status with the output of this get_exp_response().
And in here, we have to code all the error scenarios.
And let's take from the Aligner specifications all the error scenarios described here, so these four rows from here.
And let's paste that text here just to have it as a reference.
Now let's code the first error scenario.
Any access to a location on which no register is mapped.
And to find out if a register is mapped at a particular location, we should use the function get_reg_by_offset() from the uvm_reg_map.
This function has two arguments: offset, which is the address of the register, and a read bit to tell the function if this access is a read.
So let's code this.
That's it.
So this is how we can get a pointer to the register mapped at this address.
And if this register is null then we are in this scenario.
So let's code to this.
That's it.
Now for the second error scenario.
Any write access to a full read-only register must return an APB error.
For this one, we should use another function from the uvm_reg_map class called get_reg_map_info().
That's it.
So during a write access, we get the register map information for the accessed register, and this function will return this class.
And in this class, there is a field called rights, and this one is of type string.
And if this one is read-only, then we return an UVM_NOT_OK.
The value that we will find in this rights field is the value that we configured in our register block.
So, if we go here in the register block, when we added the register to the map, we also configured here the rights value.
So, whatever we configured here will be returned in this rights field from here.
And let's do something similar for the reverse case, a read access to a full write-only register.
That's it.
So, if we are doing a read and we are reading a write-only register, we should expect an UVM_NOT_OK.
Now, for the last error scenario, illegal write access to the Control register, if we go back to our spec and jump to the "Control Register", we have these two error scenarios.
So first let's check if this is a write access accessing the Control register.
That's it.
So we are checking to see if this is a write access and then with this cast we are checking to see if the accessed register is the Control register.
But now in order to implement these two error scenarios we need to figure out what values can be written with the data on the APB bus in these SIZE and OFFSET fields.
And we said in the previous tutorial that for this we will implement a function called get_reg_field_value() which will extract this information.
So let's implement this function.
So this function has two arguments: a pointer to a register field for which we want to get this information and the value of the data bus.
Now let's discuss the implementation of this get_reg_field_value() function as it is not quite straightforward.
Let's say that this function receives on this reg_data this value.
So this is in binary and we have here 32 bits.
And let's also see the layout of the Control register to see where each field is positioned.
And let's consider that we want to get from this entire 32-bit value the value of the OFFSET field.
So, this one here 100.
And these two functions that we are using will return these values.
So, get_n_bits() will return value 3 for the OFFSET as OFFSET field has a width of 3 bits and get_lsb_pos() will return value 8 as the OFFSET field starts from position 8 from here.
So, let's see how this mask value is built.
Initially, all the bits are zero.
With the first operation from here, we want to shift value 1 to the left with this many bits, so with 3 bits.
This means that the mask will become 1 0 0 0.
Then, we want to subtract value 1 from this so the mask will become 1 1 1 and then we are doing again a left shift with LSB position so with 8 bits.
So these three bits will be moved here.
So in this mask value all the bits are 0 except the ones which overlay the OFFSET field.
And now let's see how the result is built.
So initially the result is 0 and then we are doing this AND operation between mask and reg_data.
So between this one and this one.
And because in the mask value we have these 3 bits here overlaying the OFFSET then the result will be this value after the AND.
So this 100 will end up here.
And the last operation this right shift with 8 bits will move these 3 bits on the least significant position here.
So in this way we manage to copy these bits from here to here.
So now that we have this get_reg_field_value() function, let's use it in our code and implement these two last error scenarios.
First, let's extract the values for SIZE and OFFSET.
So this is how we extract the value for the SIZE field.
We pass the pointer for this register field and we also pass the data on the APB bus.
And now let's do something similar for the OFFSET.
That's it.
Now let's implement this scenario in which we should expect an error response if we try to write value 0 for the SIZE field.
And now for the scenario in which we detect an illegal combination between SIZE and OFFSET.
That's it.
Now let's implement the check in this write() function just before we make use of this operation.status.
That's it, so we are performing this check only if it is enabled from the environment configuration component.
In here we are getting the expected response using our new function and then we are comparing the expected response with whatever RTL returned and if there is a mismatch we trigger this error.
Now let's try to test our code.
First we should go to our register access test and try to do a write to the Control register with a legal combination for the SIZE and OFFSET, so 2 and 2.
And then in our predictor let's introduce a bug in our code.
Let's put here an equal sign so we are driving a legal combination between SIZE and OFFSET and the RTL will return an OK response but our code will think that it should expect an UVM_NOT_OK response.
And let's see if our error is triggered.
The simulation finished and let's look through the log.
So we have our UVM error and it is this one mismatch detected for the bus operation status.
Expected: UVM_NOT_OK.
Received: UVM_IS_OK.
And then we have the APB access printed.
So it looks like our code is working correctly.
Before we close this tutorial I want to show you one debug technique that you might find useful for you.
So if you look on this error message we get some information about what is the expected value, what is the received value, and what is the APB access but we have several error scenarios for which our environment will say that it is expecting an UVM_NOT_OK response and usually if we get such an error when we run our test we will have to look on this APB transaction and we will have to figure out why our environment generated an UVM_NOT_OK response.
So it would be very useful for us during debug to also have here the reason why the environment generated this expected response.
And we can actually code this very easily in our predictor.
What we need to do is to change the type of the result of this function get_exp_response() not to be just the expected UVM status but to be a pair of status and reason.
And for this we can create a class which contains the status field and some string, let's call it info.
And then, every time we return an expected result here, we don't simply return the status, but we return the status plus the string with the reason why that status has that particular value.
So, let's try to change our code in this manner.
Let's create a class which contains this status-info pair.
And for this let's create a file.
That's it.
So our class will be called cfs_algn_reg_access_status_info.
And now let's declare the class.
And for this scenario we can create a simple class which has no parent class.
And here let's declare two constant fields as we don't want to change their values after we created the instance.
That's it.
And because these are constants let's assign their values in the constructor.
That's it.
And now to make our life easier when we instantiate this class let's create a static function which will get us a new instance of this class.
That's it.
Now let's include this file in our Aligner package.
And let's make use of this class in the predictor.
So we need to change the return type here.
And in here instead of just returning the status we should return a new instance of this class.
And now let's add the reason.
And let's do the same in the rest of the scenarios.
That's it and now let's fix the code in the write() function.
Here we should fix the return type.
And here we should use the status field.
And now we can also print the reason.
And the reason is in the exp_response.info.
And now let's try to run and see how our error message looks like.
The simulation finished and let's look on the log to read the error.
So the error is this one and at the end we should have the reason why our environment generated this UVM_NOT_OK.
And the reason is this one: illegal access to Control - OFFSET 2, SIZE 2 and aligner data width 32.
Of course because we introduced this error in our code the message is incorrect so let's just fix this one and now when we run we should not get any error in our log.
But I just wanted to show you how a small change like this can make our life much easier because when we get a real error like this one from the RTL we don't really have to look through all the scenarios and figure out why the environment returned an UVM_NOT_OK, we will simply get that information from the error message.
And this is a technique which you can apply while debugging and it will save you a lot of debug time.
Ok, the simulation finished and now we have no UVM error.
That's it for this tutorial.
We managed to implement our custom register predictor in which we are filtering all the accesses with errors not to go to our register model and we also implemented the check for the APB response from the RTL.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
