# How we can update our register access test to make it more random

*Chapter: Debug and tests · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about how we can update our register access test to make it more random.
In the "Tests Organization" tutorial we talked about this structure of our test classes.
So in this tutorial we are going to focus on this register access test from here.
A more accurate representation of the inheritance diagram for our test is this one.
Between our register access test and the uvm_test we have this intermediate class.
In our base test we only define the environment instance.
I did not put this base class in our diagram from the "Test Organization" tutorial as this class does not contain any logic to drive any traffic on the interfaces of the DUT, so I wanted to avoid the false impression that we actually have only one test inheriting from the uvm_test class.
But let's move forward with our register access test.
We can update the run_phase() of this test to look something like this.
We can have a fork join with two branches.
On one branch we will drive random register accesses.
So, on this branch, all the APB accesses will be generated with an address value at which there is a register mapped.
On the other branch of the fork, we will generate APB accesses for which the address will be equal to a value at which there is no register mapped.
From our test, we want to control the number of accesses driven on each of these branches.
And for this, in our test, we will define two fields.
The first field will control the number of register accesses.
In other words, will control the number of APB accesses driven from this branch of our fork.
In the same manner, the second field will control the number of unmapped accesses.
So this means the number of APB accesses driven from this branch of the fork.
We can initialize both of these fields to value 100 in the constructor.
Having these two fields here will allow us to create in the future tests which we will inherit from this one and in those tests we can easily control these two fields.
For example, if we want to have a test in which we only drive unmapped accesses, we will create a class which extends from this one and in its constructor we will overwrite the number of register accesses to value 0.
Now let's go back to our run_phase() task to see exactly how we can implement these branches of our fork.
In both of these cases, we will make use of virtual sequences.
The logic for the first branch will look something like this.
We will have a virtual sequence which will drive random register accesses.
In here, we will create an instance of this sequence, we will randomize it and then start it on the virtual sequencer.
When we randomize this sequence, we can constrain a field called number of accesses from inside this sequence to be equal to our number of register accesses.
We can apply the same logic on the second branch of our fork.
We will have a virtual sequence which will only drive unmapped accesses, and when we constrain the number of accesses done by the sequence, we will use our number of unmapped accesses field.
Now let's see exactly how we can define these two sequences.
First, let's look on this random register access sequence.
First, this sequence we'll have to inherit from our base virtual sequence class as in there we defined the p_sequencer field.
Next, we will have to define that number of accesses field and we can apply a soft constraint for this one.
The body() task of this virtual sequence will look something like this.
First, we will have to get all the registers from our register block using this get_registers() function.
Next, we will have a for loop and in each iteration of this for loop we will access a random register.
So the first thing here is to pick up a random register from our registers queue.
This means that we will have to generate this index between 0 and the size of this queue.
Then we will have to pick randomly the direction for accessing the register.
And for this, we will have this function get_random_access().
Based on the result of this function, we will either read the register or write it.
When we read the register, we call this read() task.
When we write the register, we randomize the desired value and then we call the update() task.
And at the end, we wait a random number of clock cycles.
Now let's see how we can implement this get_random_access() function and this wait_random_time() task.
First, this get_random_access() function can have this implementation.
We simply randomize this result to be either read or write.
I also added as arguments for this function the register that we want to access and the index of the access.
In this implementation we are not using any of these values.
But the idea is the following: We might need in the future to actually constrain the direction for some particular register for example.
Let's say that in the future we might need a random register access test for which the Status register is always accessed with a write direction.
So for such a test, we can create a child class of this sequence, and in that class we can override this get_random_access() function to only generate write access for a particular register.
And the last API of this class is this wait_random_time() task.
And the implementation of this task is pretty simple.
We get a reference to the virtual interface, we generate this delay field here between 0 and 20, and then we use this value to know how many clock cycles to wait.
And now let's look on the implementation of our unmapped register access sequence.
In the same way, it will have to inherit from our base virtual sequence.
Also in this sequence we will have to define this number of accesses fields and our wait_random_time() task and the body() of this sequence will look something like this.
We will use this get_reg_addresses() function to get a queue with all the addresses of the registers.
Then in a for loop we will use this simple APB sequence.
The only constraint that we will apply to this sequence is this one.
We want the address of the item not to be inside our queue of addresses.
And after this item is sent, we call our wait_random_time() task.
And the last thing that we need to discuss is the implementation of this get_register_addresses() function.
In this function, first we need to get all the registers from our register block.
And then for each register and for each byte of the register, we push in our addresses queue the address of the register plus the byte index.
So, for example, for a register mapped at address 0 and having 32 bits in width, we will push in our addresses queue value 0, 1, 2, and 3.
I'm making here an assumption that the width of all the registers is always a multiple of 8, but I think it's safe to consider that this is true for all the registers.
That's it for this tutorial.
We talked about how we can update our register access test to make it more random and in particular we discussed about the sequence for sending the random register accesses and also the sequence for sending accesses to unmapped locations.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
