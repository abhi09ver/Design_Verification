# Register block

*Chapter: Register model (RAL) · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to code together the register block.
The starting point is the "UVM Register Block - Practice" project which we need to copy.
Let's resize the windows.
The first thing that we need to do is to create the cfs_algn_reg_block file.
And now let's include this file in our register package.
And now let's declare the register block class.
The next thing that we have to do is to declare our four registers.
That's it, so we have the four registers with the same name as in the Aligner documentation, all in uppercase, with "rand" attribute and having as type the classes that we declared in the previous tutorial.
Now let's create that build() function and add the necessary code in it.
First, let's instantiate the registers using the factory method.
That's it.
Now let's call the configure() method from each of these registers.
That's it.
Now let's call the build() method from each of these registers.
That's it.
Now let's create the address map by calling that create_map() function and we will place the output of this function into that default_map field.
So when we call this create_map(), we have to pass a name and we can place here any name that we want.
Then the base address we discussed in the previous tutorial that we wanted to be 0 and bytes is 4 because the APB bus has a data bus of four bytes in width.
Endian format is little-endian and byte addressing is 1 because two consecutive addresses are accessing byte 0 and then byte 1 and so on.
Now one thing that we can do here is to set that check-on-read equal to 1.
So let's call that setter.
So this line will enable the checks on the read data, so it will compare the data returned by the RTL with the mirrored value.
The last thing that we have to do in this build() function is to add the registers to this default_map.
So let's do this at the end of the function.
That's it.
So we called this add_reg() function for each of our 4 registers and we set the offset for each of those and then the access rights.
And you can see here that the access rights are read-write for Control, Interrupt Requests Enable and Interrupt Requests, because also in these registers we can write and the only register which is read-only is the Status because in this one there is no field which we can write.
The next thing that we have to do is to create the instance of our register block and we will place that instance in another component called "model" and that component we have to instantiate in the environment.
So the next thing that we have to do is to create the file for this model component and then we will declare the class in it.
So let's do this.
Now let's include this file in our Aligner package.
And now let's declare the model class which is an extension of uvm_component.
That's it.
Now let's declare the register model.
And in the build_phase() of the Aligner model we can create the instance of our register block.
We should create the instance of the register block only if the handler is null.
The handler can be already allocated if we are running our environment at system level.
In that scenario, the register block is created at system level environment and this is only connected as a pointer.
So this is why this "if" exists here.
And once we created the instance of the register block, we must call the build() method.
That's it and once we build our register block we no longer want to do any changes to its structure so we should call the lock_model() function.
That's it.
Now the only remaining thing is to create an instance of this model in our environment.
So this is the handler and in the build_phase(), at the end, we can create the instance.
That's it.
Now let's try to run a simulation to see that we don't have any compilation issues.
The simulation runs successfully.
We have no errors in our log, so we managed to implement correctly our register model.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
