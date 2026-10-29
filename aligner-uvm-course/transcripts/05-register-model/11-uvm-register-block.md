# UVM register block

*Chapter: Register model (RAL) · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about the UVM register block.
In the previous tutorials we implemented the classes for the registers inside our Aligner but now it's time to wrap these classes inside the register block.
We will build this register block with the help of a class from the UVM package called uvm_reg_block.
And the way we use this class is by creating a child class from this uvm_reg_block and we will call it cfs_algn_reg_block.
Inside our new class we will create the instances of our four registers from the Aligner RTL.
Now let's look on the API of this uvm_reg_block in order to understand the functions that we need in order to create our cfs_algn_reg_block class.
The first thing that we need to know about is the constructor of the uvm_reg_block.
Just like for the uvm_reg it has two arguments.
The first, "name", is the name of the instance and the second one controls the coverage, this has_coverage.
And in our case we will use the default value UVM_NO_COVERAGE.
The "UVM User Guide" provides a set of rules which we need to follow in order to build an extension from this uvm_reg_block.
And let's go through the rules that we need to be aware of in the next tutorial when we will implement this class.
The first rule is this one: The block type must contain a class property for each register it contains.
This means that in our reg block class we have to declare a property for each register of the Aligner RTL.
The second rule is this one: The name of the register class property shall be the name of the register.
This is an easy rule to understand.
It means that we have to use the same names as in the Aligner documentation when we name these fields from our reg block class.
The third rule is this one: The type of the register class property shall be the name of the register type.
This means that when we declare these fields, we cannot use for example the generic uvm_reg class.
We must use the classes that we defined in the previous tutorial.
The fourth rule is this one: The register class property shall have the "rand" attribute.
So this means that we have to put this "rand" attribute in front of all of our registers.
And the reason behind this is that in this way we will be able to randomize the entire register block.
The fifth rule is this one: The register names shall be in all uppercase or prefix with underscore.
So in the case of the register names part of the register block we actually have two options: either uppercase or prefix with underscore.
And in our case we will go with the first option, so we will have all the names here in uppercase.
And the last rule that we need to be aware of is this one: A virtual build() function with no arguments shall be implemented.
This means that in our Aligner reg block class we need to declare this build() function just like we did for the registers.
The "UVM User Guide" also provides rules about what we should put in this build() method.
So let's go through these rules together.
The first rule is this one: The build() method shall instantiate all register class properties using the class factory.
This means that in our build() function, we will create the instances of our four registers using this create() function.
The next rule is this one: The build() method shall call the configure() method of all the register class properties.
We did not discussed in the UVM Register tutorial about this configure() method inside the uvm_reg class but this is a good time to mention this.
So, this is the API of the uvm_reg class that we discussed in the previous tutorial and in this uvm_reg class there is one other function called configure().
And let's see the signature of this function.
It has these three arguments: blk_parent, regfile_parent, and hdl_path.
For the first argument, blk_parent, we need to pass a pointer to our register block.
The second one, regfile_parent, we need this when we wrap our register inside the register file.
But this is not the case for us so we'll leave this to null.
The third argument, hdl_path, is used by a feature of the UVM library called Back-door Access.
This Back-door Access allows you to access directly the registers inside the DUT with SystemVerilog functions like deposit or probe.
So you can actually bypass the physical interface for accessing the registers, in our case the APB interface.
But we will not use this feature, so we will leave this hdl_path equal to an empty string.
If you want to learn more about this feature, you should search in the "UVM User Guide" for back-door accesses.
But coming back to our rules, when we have to implement this rule, it means that our build() function will look like this.
We'll call this configure() function of all the registers.
And in here we will set the blk_parent argument to value "this" in order to pass the pointer to our register block.
The third rule is this one: The build() method shall call the build() method of all the register class properties.
Remember that in the previous tutorial we implemented a build() method in each of the registers and now it's time to call that method, so our build() method from the register block will call the build() method of all the registers.
Now that we created the instances of these registers and then configured them, it's time to allocate these registers to their particular addresses.
And we can do this with something called a register map, and this map will hold the information about what register can be accessed at a particular address.
This APB map is nothing more than an instance of another class part of the UVM package called uvm_reg_map.
To create an instance of this uvm_reg_map, we don't use directly its constructor but actually we use a function part of the uvm_reg_block called create_map().
The signature of this create_map() function is this one.
It has these five arguments.
The first one, "name", is the name of the instance of this map.
The second one, base_addr, is an address from which we place all other registers.
And in our case, because the Control register starts from address 0, we will use as the base address value 0.
And when we specify at which address a register is located, we actually specify an offset relative to this base address.
The next argument n_bytes represents the width, in bytes, of the data bus of our register access protocol, in our case the APB.
And we have 32 bits for the data bus so this means 4 bytes, so we will use value 4 for this argument.
The next argument endian it's the endian format so we will use little endian for this one.
And the last argument byte_addressing controls whether consecutive addresses are 1 byte apart or n_bytes apart.
So when this byte_addressing is 1, address 0 refers to byte 0, address 1 refers to byte 1, address 2 to byte 2 and so on.
But when this byte_addressing is 0, address 0 still refers to byte 0 but address 1 refers to byte 4, address 2 refers to byte 8.
So it will access bytes with this n_bytes step.
So, because this uvm_reg_map represents a model of a physical interface used to access the registers part of an RTL, we have to call this create_map() to create maps for each of the physical interfaces part of an RTL which are used to access the registers.
But in our case, we only have one interface, our APB interface.
And in such scenario, we actually have an option not to declare this APB_MAP here under the register block, but we can use a predefined field under the uvm_reg_block called default_map.
So once we create an instance of this uvm_reg_map, we need to add registers to it.
And we can do this with the help of a function called add_reg(), part of uvm_reg_map.
The signature of this function is this one.
The first argument is a pointer to the register that we want to add to the map.
The second argument is the offset relative to the base address of the map at which the register can be accessed.
So the formula for the absolute address of a register is equal to map base address plus this offset.
In our case we will set the base address of the map to value 0x0 and then the offset will be 0x0 for Control, 0xC for Status and so on.
The third argument represents the access rights for the register.
This is quite similar to what we had for the register fields, and in that case we had quite a lot of possibilities for the access rights like write-one-clear, read-write, write-only and so on.
For the register, we only have three possible values for this field: read-write, write-only, and read-only.
The next argument unmapped, we usually use this with value 0, but you can use this with value 1 when you have the scenario in which a register is not mapped.
This means that it does not have an address to access that particular register.
And in that case, you have to provide through this frontdoor argument a way to access that particular register.
But because in our case all the registers are mapped, we will not use these two last arguments.
Creating the address map and adding registers to this map is also mentioned in the rules governing the build() method.
So let's see those rules and how our build() method will look like when we take them into consideration.
The fourth rule is this one: The build() method shall create the address map by calling the create_map() function from the reg block.
And the next rule is this one: If the block does not contain any named address maps then the default_map field from the register block must be used.
So this means that our build() function will look like this: It will call this create_map() and allocate the result to this default_map field.
And the last rule is this one: The build() method shall call the add_reg() function from uvm_reg_map for all mapped registers.
This means that our build() function will have to call this add_reg() for each of our registers.
And we will pass to this add_reg() function the pointer to the register, the offset, and the access rights.
So these are the rules that we need to be aware of in the next tutorial when we will implement our register block class.
So we have 6 rules for building the register block class and 6 rules for defining the build() method.
Now that we know how to create our register block class, we need to create an instance of it and an instance of a register block is called a register model.
And we will place this register model inside another component called Model from our environment.
In this Model component we will create the model for the behavior of the Aligner.
So it's only natural to also place here the register model.
Before we close this tutorial, there are two other functions that I want to talk to you about from these two classes.
The first function is part of the uvm_reg_block and it is called lock_model().
You can call this function in order to lock, or protect, your register model.
Because once locked you cannot do any structural changes to your register block.
So normally we call this function once we finished adding and configuring all the registers.
The other function that I want to talk to you about is part of the uvm_reg_map class and it is called set_check_on_read().
By default, checks on the read data are disabled, so we have to enable them as we want to check all the return data by the RTL.
And by the way, at least in the version that I have for the UVM documentation, there is a typo here.
It should say: By default, check-on-read is turned off.
To get more information about the classes that we discussed, you can go to the "UVM Class Reference" manual.
Under chapter "Register Layer", "Register Model", you have these two sections: "Blocks", in order to get the description for the API of uvm_reg_block class.
And the other section is this one: "Address Maps" where you get the description of the API of this class uvm_reg_map.
Also in the "User Guide" you can find more useful information under the "Using Register Layer Classes", "Constructing a Register Model", you have this chapter "Block Types". where you'll find all the rules that we discussed in this tutorial and also there is a dedicated chapter for the build() method here.
And you'll find in this section all the rules that we discussed regarding the build() method.
There are two other chapters that I strongly recommend you to go through.
The first one is this one "Integrating a Register Model in a Verification Environment" and the second one is this one "Integrating a Register Model".
But also in the next tutorials we will discuss more about the information which is part of this chapter here.
That's it for this tutorial.
We discussed about the UVM Register Block and its API.
We also discussed about the UVM Register Map and its API.
We talked about the rules that we need to be aware of for defining the register block and its build() method.
And finally, I showed you where you can find more information in the UVM documentation about the classes that we discussed.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
