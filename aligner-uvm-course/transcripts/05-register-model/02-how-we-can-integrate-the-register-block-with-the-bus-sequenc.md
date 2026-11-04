# How we can integrate the register block with the bus sequencer

*Chapter: Register model (RAL) · source: attached*

Hi my name is Cristian Slav and in this tutorial we are going to talk about how we can integrate the register block with the bus sequencer.
This is the current image of our verification environment and so far we managed to connect the register model with the monitor.
But this time we want to connect the register model with the sequencer.
And by doing so we enable the usage of some tasks from the uvm_reg class.
And I'm referring here to these three: write(), read(), and update().
Using these three tasks will allow us to write tests faster and also independent of the protocol used to access the registers.
For example, currently we have this code to write to the Control register.
We create an APB sequence and then we randomize the sequence with the address, direction, and data and then we send that sequence to the sequencer.
However, we can replace this code with this one.
And in here we only specify that we want to write to the Control register with this data.
So first of all, we don't mention here the protocol and we only write one line instead of these from here.
So you see there is a big difference between writing a test in this way versus this way.
But now let's see what our register model needs to know in order to be able to generate an APB access from this line of code.
So when we are writing a line like this one, the register model is able to transform this write request into an instance of this struct uvm_reg_bus_op.
So it can set in the background the kind to be write because we called the write() task, it knows the address of the Control register because it knows where it is mapped, and it also knows the data that we want to write in the register.
And once the register model has this information, it needs a way to transform this uvm_reg_bus_op to the sequence item used by the sequencer.
In our case is that cfs_apb_item_drv.
And this transformation stays in the adapter.
If you remember from the previous tutorials, we said that the adapter also has this function reg2bus().
We left this function empty but now it's time to implement it.
So in this reg2bus() we will transform this uvm_reg_bus_op to our cfs_apb_item_drv.
So once the register model has access to the item used by the sequencer, it needs to send that item.
And in order to do this it needs a pointer to the sequencer.
And we can configure this pointer to the sequencer via a function of the uvm_reg_map class.
That function is called set_sequencer().
And the signature of this function is this one.
It has two arguments: sequencer and adapter.
Sequencer is the pointer to the APB sequencer and adapter is a pointer to our implementation of the uvm_reg_adapter.
So when we call one of these three tasks write(), read() or update() the register model will transform that call to this uvm_reg_bus_op.
Then it will use the pointer to the adapter to transform this information using the reg2bus() function to the item with which the sequencer is working and once it has that information it will use the pointer to the sequencer to send that item on the APB bus.
And in this way we can make use of these functions like so.
If we want to do a write we can call this write() function.
But doing so we must make sure that we know the position of each field that we want to write.
The alternative is to use the desired values and the set() functions of the fields.
So we can replace this write() call with something like this.
We can set the desired values for the OFFSET and SIZE and then we simply call the update() and in this way we no longer have to care about the position of OFFSET and SIZE fields in the Control register like we had to do here.
The other task that we can use is the read(), so a read access will look like this.
And as you can see, in this write accesses either via the write() task or the update() task, we are specifying directly the values that we want to write.
But we also have the possibility to randomize the register.
And in the test we can have some code like this one.
First we randomize the Control register and then we do an update, but remember that for the Control register, we cannot write any value in the fields SIZE and OFFSET, we have some limitations.
And we can implement those limitations in a set of constraints that we can write in the Control register class.
However, the "UVM User Guide" provides some rules when it comes to writing constraints in the UVM register class.
You can find these rules in the "UVM User Guide" in chapter "5.5.2.1 Class Properties and Constraints".
This is a subchapter of the UVM Reg section of the "UVM User Guide".
The first rule that we can extract from this text is this one: Constraints should be defined in separate blocks for each aspect being constrained.
And the second rule is this one: The name of a constraint shall be indicative of its purpose.
So taking these two rules into consideration, in our Control register class, we can actually create two blocks of constraints.
One to define the legal value for the SIZE, and this one should be different than zero, and one to define the legal combination between SIZE and OFFSET.
The next rule that we can extract is this one: Constraints shall constrain the "value" class property of each field in the register.
This means that for example when we are writing the constraint for the legal SIZE, we should use the "value" class property of the SIZE register field in order to write this constraint.
The last rule that we can extract is this one: Additional state variables may be added to the register type class if they facilitate the constraints.
And this is exactly what we need to do for our Control register.
In our Control register, we need to have the information about the Aligner data width in order to write the constraint for the combination between SIZE and OFFSET.
This means that we will have to declare in the register Control this extra information here.
And remember from the previous tutorials that we had a rule about adding fields or functions to a register class.
The name of those properties must be with capital letters.
So adding these constraints will allow us to do some random access to the Control register, and whenever we randomize the values in the Control register, we know that those values will be legal.
And as you will see in the next tutorial, we will be able to add these lines of code directly in our test.
However, the "UVM User Guide" suggests that we should wrap these accesses to the register in a sequence which extends from uvm_reg_sequence.
This uvm_reg_sequence is a class, part of the UVM library, which is defined like this.
It has as a parameter the base class from which it extends.
So this gives us a lot of flexibility and the API of this uvm_reg_sequence is quite big and I strongly suggest you to look in the documentation for all the functions and tasks defined here but most of them are used to access the registers so you will find tasks like write_reg(), read_reg() and so on.
Now, let's look in the documentation to see where you can find more information on this subject.
First, let's look in the "UVM User Guide".
Here we have several chapters relevant for us.
Under "Using the Register Layer Classes", "Integrating a Register Model", we have this chapter "Integrating Bus Sequencers".
And in here you'll find three approaches for integrating the bus sequencers and in this tutorial we talked about the first one.
The next relevant chapter for us is this "Transaction Adapter" where you will find information about how to implement this reg2bus().
And then for information about how to randomize the fields inside a register we have this chapter "Randomizing Field Values".
And there is another section under "Constructing a Register Model" "Register Types".
Here there is this section "Class Properties and Constraints" where you can find the rules that we talked about.
The other source of information for us is the "Class Reference" manual and here you can find information if you go to the "Register Layer", "DUT Integration", "Register Sequences" and here you can find more information about this uvm_reg_sequence.
That's it for this tutorial.
We talked about how we can integrate a register model with a bus sequencer, and for this we look through the relevant API of the Register Map class.
Register Adapter class and Register class.
We also talked about the rules that we need to be aware of when we are constraining the register class properties and finally we looked through the documentation to see where we can find more information about this.
In the next tutorial, we will implement all this together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
