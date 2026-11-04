# Four register classes of the Aligner RTL

*Chapter: Register model (RAL) · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to code together the four register classes of the Aligner RTL.
The starting point is the "UVM Register Field and UVM Register - Practice" project from EDA Playground which we need to copy.
And let's resize the window.
The first thing that we have to do is to create a separate package for our register classes and we will call this cfs_algn_reg_pkg.
Now let's include this package in our Aligner package and let's also import it.
Next, let's create the class for our Control register.
But first let's take a look in the documentation and see how the Control register looks like.
So we can jump to this section "3.1.
Control Register".
And in here we have the layout of the register.
So we have this SIZE field which starts from 0 and it has a width of 3.
Then OFFSET has a width of 2, from offset 8.
And CLR a width of 1, from offset 16.
The SIZE is read-write, OFFSET is read-write and CLR it's write-only.
So let's do this.
First we have to create the file.
Let's include this file.
And now let's declare the Control class.
Remember that the new() constructor of the uvm_reg has three arguments: name, n_bits and has_coverage.
So let's fill in those.
So the name, it's this one that we passed through the new constructor. n_bits is the width in bits of the register.
So it's this width here.
So it's 32 in our case.
And for has_coverage, we are going to use UVM_NO_COVERAGE as we are not going to yet implement the coverage in the registers.
Next, let's declare the three register fields part of the Control register: SIZE, OFFSET and CLR.
And when we declare these fields, these ones must be public, they must be in all uppercase and they must have that "rand" attribute in front.
So let's do this.
That's it.
Now let's declare that build() function in which we are going to instantiate those register fields and then we are going to call that configure() function.
So I used here the three arguments of the create() function: name is the name of the register field: "SIZE". parent we don't have here an UVM component so the parent is null, and the context is the get_full_name() of the register.
And we can do the same thing for the two other register fields.
Next, we must call that configure() function for each of the register fields.
We can look in the "UVM Class Reference" manual to see the arguments of this function and we have to provide a value for each of those arguments.
That's it, so the parent is the pointer to the Control register class. size is 3.
Least significant bit position is 0.
And this is because the size of this SIZE register field is 3 bits in width.
The least significant bit position is this one from 0.
As access we have the value read-write just like it is stipulated here in the documentation. volatile is zero and this is because we are not expecting the register inside the RTL to change very fast. reset value it's 1 and this is also in the documentation for the SIZE: the reset value is this 1 here.
And then has_reset is 1 to take into consideration this value.
We want the register field to be randomized so we set this to 1, is_rand.
And then individually_accessible it's 0 and this is because we cannot access only this register field when we are trying to do an access on the APB interface.
When we are accessing the APB interface we are accessing the entire register not just one field.
And now let's call this function for OFFSET and for CLR.
OFFSET has a size of 2 and the least significant bit position it's actually 8.
The access is also read-write the reset value for the OFFSET it's actually 0.
And that's it.
Let's double check this information in the spec.
So for the OFFSET it's offset it's 8, its size is 2, it is read-write and the reset value is 0.
And for CLR we are going to use as offset value 16, as size value 1, the access is write-only and the reset value is 0.
So let's do this for CLR.
That's it.
Now the next register that we are going to code is the Status register.
The Status register has these three register fields: CNT_DROP, RX_LVL and TX_LVL.
So let's code these ones.
First let's declare the file.
And now let's include it.
And let's declare the Status register class.
So, just like for the Control, we called this new() constructor of the uvm_reg with the value name will be this one, n_bits is 32 because the Status register has a width of 32 bits.
And finally, has_coverage, we are going to use the predefined value UVM_NO_COVERAGE.
Next let's declare the three register fields.
And now let's declare that build() function.
And now let's call the configure() function.
We must pay attention to any copy paste error here.
And even though this is a Status register and for example this drop counter can increment quite fast, we are still going to use volatile as 0 as we are going to try to model this CNT_DROP accurately.
So this RX_LVL has a size of 4 and lsb_pos is 8.
Let's also double check this in the documentation.
For RX_LVL it starts at 8 and it has a size of 4.
And for TX_LVL now again has a size of 4 and it starts at index 16.
That's it.
Next, we must code that "Interrupt Requests Enable" and let's look in the documentation to see how this register looks like.
So it has these five fields starting from offset zero.
So we have RX_FIFO_EMPTY, RX_FIFO_FULL, TX_FIFO_EMPTY and TX_FIFO_FULL, and then MAX_DROP.
The size of all these fields is 1, the offset is 0, 1, 2, 3 and 4.
The access for all of them is read-write and the reset value is 0.
So let's do this.
First we are going to declare the file.
Let's include it.
Let's declare the class.
Also for the "Interrupt Request Enable" the n_bits is 32 as it has a width of 32.
So all of our registers have this width.
And now let's declare those fields.
And finally we must declare that build() function.
And let's call the configure() function of each of the register fields so this is for the RX_FIFO_EMPTY the only difference for this one is that it has the least significant bit position 1.
This one has 2.
TX_FIFO_FULL has lsb_pos equal to 3.
And finally, MAX_DROP will be at offset 4.
That's it.
Now the last register is the "Interrupt Requests" which is quite similar to "Interrupt Requests Enable"with the only difference is that the access is write-one-clear but the rest of the values: offset, size and reset are identical with the "Interrupt Requests Enable".
So let's also code this one.
Let's include the file.
And let's try to copy paste the definition from the "Interrupt Requests Enable", but we must pay attention to any copy paste issue.
So the register is "Interrupt Requests", the name of the fields is the same and the only difference is the access.
That's it.
Let's save and try to run our project to see if we have any compilation issue.
The simulation finished.
Let's look through the log to see if we have any errors.
And no, everything looks good.
So we managed to implement correctly our register classes which are modeling the four registers inside the Aligner.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
