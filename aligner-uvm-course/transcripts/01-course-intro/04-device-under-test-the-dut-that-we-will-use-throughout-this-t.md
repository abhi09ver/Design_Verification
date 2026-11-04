# Device under test, the DUT that we will use throughout this training in order

*Chapter: Course introduction · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about the device under test, the DUT that we will use throughout this training in order to learn how to do module level verification.
Our DUT is called Aligner and you can find its datasheet in the downloadable materials of this training.
In this tutorial I will explain to you all the features of this Aligner but I strongly recommend you to go through this documentation on your own to get a feeling of what you should expect in a real project.
When you are working in a real project you will have to go on your own through the documentation and understand all the features of the DUT that you will have to verify.
As its name suggests, the main feature of our Aligner is to align some data.
It has an interface through which it receives unaligned data.
We refer to this interface as the RX interface.
RX stands for reception.
Once our DUT aligns this data, it will send that aligned information on the TX interface.
TX stands for transmission.
We also have the possibility to access the registers of our Aligner.
Through these registers, we can configure the behavior of our Aligner or we can read the status of our DUT.
Let's talk about the main feature of our Aligner which is to align the data.
Our DUT receives the unaligned data on the RX interface, aligns it and then sends it out on the TX interface.
This alignment happens at byte level.
On both of these interfaces the Aligner has a data bus of 32 bits in width.
This means 4 bytes of information.
We can visualize these 4 bytes of data as lanes.
On the RX interface we have 4 lanes numbered from zero to three, and the same thing is valid on the TX interface.
We can specify what are the lanes containing valid data via two fields: size and offset.
Size represents the number of bytes or the number of lanes containing valid information.
Offset represents the position of the valid information relative to the first lane.
So, when we are sending on this RX interface a transaction with size 1 and offset 0, it means that only the first byte from here is valid.
We can use different combinations for size and offset but not all of them are legal.
So, let's go through all the legal combinations of size and offset.
We also have size 1 and offset 1 to send the information on this lane.
For size 1 and offset 2 the information will be passed through this lane and the same for size 1 and offset 3.
We can also send 2 bytes at a time and when we are sending 2 bytes we have two possibilities for the offset, either offset 0 or offset 2.
The rest of the values for the offset are considered illegal.
A size of value 3 is considered illegal for any value of offset and the last legal combination is size 4 and offset 0.
An example of an illegal combination is this one: size 3 and offset 0.
In our tests we will also have to send these illegal combinations of size and offset because the correct behavior of the Aligner is to reject those transactions.
So we will have to test this.
But let's see all the legal combinations of size and offset.
For size 1 we can use any value for the offset.
For size 2 we can use offset 0 or 2, and for size 4 we can only use offset 0.
Any other combination of size and offset is considered illegal and the Aligner will have to reject that transaction with an error.
Now let's see exactly how this alignment happens.
Remember that I told you that our DUT also have some registers which we can configure in order to control its behavior.
And in order to control how the data is aligned, we have a register called Control register.
This register has a width of 32 bits.
Out of all these bits, some of them are reserved so you'll see them in the documentation as read-only.
Our Control register has two register fields relevant for the alignment functionality.
These are SIZE and OFFSET.
We can read and write these register fields, so this is why you will see this RW.
This stands for readable and writable.
With these two fields, we can control how the data will be aligned.
With the SIZE field, we will control how many bytes will be outputted with each transaction on the TX interface, and with OFFSET field, we will control where those bytes will start on the TX lanes.
So, for example, if we have the OFFSET register field equal to 2 and SIZE equal to 2, then this means that we want the Aligner to align the data on lanes 2 and 3.
Let's see a short animation on how the Aligner will do this alignment.
When the first byte is received on the RX interface, the Aligner will position it on the first lane on which it has to send that data out.
So, in our case it will position it on lane 2 because the OFFSET in the Control register field is 2, but based on the SIZE field from the Control register it will have to send every time 2 bytes of data.
So, the Aligner will have to wait for at least one other byte to receive it on the RX interface.
Once it aligned the number of bytes specified in the SIZE register field, in our case 2, it will send those bytes on the TX interface and the process is repeated over and over again.
So at the end we will get on the TX interface this nicely aligned data based on the OFFSET and SIZE register fields from the Control register.
And let's see another example where we have OFFSET 0 and SIZE 4.
This means that we want our DUT to send 4 bytes of information on the TX interface starting from offset 0.
So our Aligner will receive the information on the RX interface and it will wait until it has enough information to send it on the TX interface.
So at this point our Aligner has inside 5 bytes of information but it will have to send only 4 of those bytes.
So in such a scenario it will have to split this last transaction to only send 4 bytes of information.
This remaining byte will be placed on lane 0 and our Aligner will again have to wait to have inside at least 4 bytes of information.
And in this scenario again it will have to split this last RX transaction, take the first 3 bytes and once it has a complete TX transaction it will send it on the TX interface.
So splitting those RX transactions in order to take enough bytes of information to build the TX transaction is an important feature of our DUT that we will have to verify.
Inside our Control register, there is a third field called Clear.
The access write of this register field is write only.
This means that we can only write this register field, we cannot read it.
If we try to read it, we will always get back from the RTL value 0.
This register field is part of another feature of our DUT called Drop Counter.
Remember that I told you that on the RX interface we can also send illegal RX accesses.
Our RTL will have to reject or drop these illegal accesses but it will also have to count how many of these accesses dropped.
Our RTL has a register called Status register and in here there is a field called Drop Counter which will count how many of these illegal accesses were dropped by the RTL.
This register field is read-only because it only gives us a status, we don't have any reason to write this register field.
The same thing is valid for the rest of the register fields from the Status register.
In the Aligner specifications, you'll find a formula which will tell you how to determine if an access is legal or not.
Our Aligner, which is a Verilog module, has a parameter called Aligner Data Width.
With this, we control the width of the data bus.
In our case, we will verify the Aligner with a data width of 32 bits.
And the formula is pretty simple.
Aligner data width divided by 8 means the number of data bytes on the bus.
So, if the number of data bytes plus the offset modulo size is not equal to 0, then this means that we have an illegal RX transaction.
So let's see how this drop counter changes.
Initially, this drop counter is equal to zero.
When our DUT receives an illegal packet, it will have to drop it.
So this means that on the RX interface we'll have to respond with an error response and in the same time it will have to increment our drop counter.
And it will do this for all the illegal transactions received on the RX interface.
Because the width of this register field is 8 bits, its maximum value is 255.
When this register field reaches this maximum value, it will remain at this value even if there are other illegal transactions on the RX interface.
In other words, it will not wrap back to value 0, it will stay at this maximum value.
At this point, we can take advantage of this Clear register field from the Control register.
If we write value 1 in this Clear register field it will clear the drop counter.
So that's everything there is about this drop counter feature.
And now let's talk about the other two register fields from our Status register: the RX and TX FIFO levels.
To understand this feature of our DUT we will have to look on the block diagram of our Aligner.
This is the block diagram showing what are the internal components of our Aligner.
Right on the RX interface, our Aligner has inside this RX Controller.
This is the submodule which determines if an access is illegal or not.
If the RX transaction is legal, then it is pushed into this RX FIFO.
The RTL keeps track of how many RX transactions are in this RX FIFO via this RX FIFO level register field from the Status register.
The next submodule in the Aligner is this Controller.
The role of this Controller is to pop data from the RX FIFO, align it, and then push it in the TX FIFO.
We can get the level of this TX FIFO via this TX FIFO level register field from the Status register.
The last submodule on this data path is this TX Controller and its job is to pop data from the TX FIFO and drive it on the TX interface.
The Aligner also has inside a submodule which is managing the registers of the Aligner.
But let's see a short animation of how the data flows through our Aligner and how these two register fields are changing with that data.
When there is a legal RX transaction received, that one ends up in the RX FIFO.
At this point, the RX level is incremented to value 1.
This shows that there is one transaction in the RX FIFO.
These two register fields, RX and TX FIFO levels, keeps track of how many transactions are in these FIFOs, not the number of bytes.
So in this case in the RX FIFO we have one transaction with a size of 2 bytes so the level is 1 because there is only one transaction.
When there is a second RX transaction that one is also pushed in the RX FIFO so the RX FIFO level is incremented to 2.
Remember the job of the Controller is to pop data from the RX FIFO and try to align it.
So whenever the data is popped the RX level it's also updated.
In this case it's decremented to value 1 because we have only one transaction in the RX FIFO.
Now let's assume that in the Control register we have these values for OFFSET and SIZE.
This means that we want our Aligner to send only one byte at a time from offset 0.
So inside the Controller the Aligner will have to split this transaction and push one byte at a time in the TX FIFO.
So, at this point the TX FIFO level is incremented to 1 because the TX FIFO has inside one transaction.
When the second transaction is pushed in the TX FIFO, the TX level is incremented to value 2.
If at this point this last entry from the RX FIFO is popped and then pushed in the TX FIFO, then the RX FIFO level becomes 0 and TX FIFO level is incremented to value 3.
In the last stage of this data flow, the TX Controller will start to pop data from the TX FIFO and send it on the TX interface.
With each pop, the TX level is decremented.
So this is how these RX and TX FIFO levels are incremented and decremented.
The next feature of our RTL is represented by the Interrupt Requests.
To understand this Interrupt Requests feature we need to look at two registers.
One is called Interrupt Requests Enable and the other one is called Interrupt Requests.
Both of these registers have the same layout.
They have one register field for each type of interrupt request that our RTL can send out.
In the Interrupt Requests Enable register we have an enable bit for each particular interrupt and in the Interrupt Requests Register we have a field which will tell us if that interrupt happened.
The enable bits are readable and writable, so we can control them through the Register Access interface, and the register fields from the Interrupt Requests register are write one clear.
This means that if we write 1 in a particular register field, then we clear that register field.
If we write 0, nothing will happen.
Our Aligner has an output signal called interrupt request.
This is a pulse signal so it will be valid for only one clock cycle and it will become one every time there is an interrupt request happening.
So let's see all the types of interrupts that can happen in our Aligner.
We have 5 types of interrupts.
The first one will signal when the drop counter reached the maximum value, that 255 value.
The second one will tell us if the TX FIFO became full.
The next one will tell us if the TX FIFO became empty.
And the last two will do the same thing but on the RX FIFO.
RX FIFO became full, RX FIFO became empty.
Whenever one of these events happened, then the corresponding register field from the Interrupt Requests register is set to value 1.
These register fields are implementing a sticky behavior.
This means that they will retain value 1 even after the condition which sets them is no longer valid.
So for example, when the TX FIFO becomes full, the TX FIFO full interrupt request is set to 1, so this one from here, and it will remain 1 even after the TX FIFO it's no longer full.
And the only possibility to clear the value is to write 1 in this particular register field.
But let's continue with the logic for building that interrupt request output signal from our Aligner.
When such an interrupt request is happening, then that signal is put through an AND gate with the corresponding register field from the Interrupt Requests Enable register.
And then the output of all these AND gates go through an OR gate.
And this is how the interrupt request output signal from the RTL is built.
So on the output of our Aligner you'll see a pulse like this one whenever an interrupt request is happening and that interrupt request is enabled.
And now the last feature of our Aligner RTL is the register access.
The protocol used to access the registers is called APB.
This is a standard protocol for which you can find the specifications online, but we will also talk about the signals part of this protocol and also the rules for driving these signals.
In our Aligner RTL, we have four registers: Interrupt Requests, Interrupt Requests Enable, Status, and Control.
In the specifications, you'll find a mnemonic for each of these registers.
In order to access these registers, we need to know their addresses.
In the address space of our Aligner, these registers are positioned in the following way: The Control register is mapped at address 0.
The Status register, it's mapped at address C.
Interrupt Requests Enable register, it's mapped at address F0.
And finally, Interrupt Requests register is mapped at address F4.
So we will use these addresses when we try to access the registers via the Register Access interface.
And let's see how reads and writes will look like on this register access interface.
On the register access interface this is how a write will look like.
First let's go through all the signals.
We have the address to specify the address of the register that we want to access.
We have the PWRITE signal to specify if we want to write or read the register.
With PSEL and PENABLE we control the phases of the access and with PWDATA we specify what we want to write in the register.
So these are all inputs inside our RTL and then the RTL will output this PREADY to let us know that the transfer ended.
The transfer has two phases.
The first one is called Setup phase.
In this one we drive address, write, and data and we specify that we want to drive the Setup phase by driving PSEL equal to 1 and PENABLE equal to 0.
The Setup phase will always last for one clock cycle.
After the Setup phase we need to go into the Access phase.
We specify to the Aligner that we are going into the Access phase by driving PSEL equal to 1 and PENABLE equal to 1.
The Access phase will last until PREADY becomes 1.
In this case in which we don't have any wait states, PREADY becomes 1 in the same time with PENABLE, so the entire transfer ends here.
One other rule is that we have to keep all the signals constant. from the beginning to the end of the transfer.
So this means that we need to keep constant address, write and PWDATA.
We can also have transfers with wait states.
This means that the Access phase will continue until PREADY becomes 1.
So in this case we have these wait states here.
The read access looks quite similar.
For a read we need to drive this PWRITE equal to 0 and we will get the read data on this PRDATA signal.
This one is valid when PREADY becomes 1.
The same thing we can have a transfer with no wait states or a transfer with wait states.
The Aligner also has the possibility to respond with an error for our register accesses.
For this, there is a signal called PSLVERR which is valid when PREADY is 1.
So if this signal is 1, then this means that we have an error response.
If this signal is 0, then this means that the transfer was OK.
The same signal PSLVERR is also used for the read accesses.
There are three scenarios for which our Aligner RTL will respond with an error response.
We will get an error response when there is an access to an unmapped location.
We will also get an error response when we try to write the Status register.
And finally, we will get an error response if we try to write in the Control field an illegal combination for OFFSET and SIZE.
So, for example, if we try to write SIZE equal to 3 and OFFSET equal to 1, then this is an illegal combination and we should expect an error response.
Let's see an example with some waveforms for accesses in the Control register.
This is the layout of the Control register with the SIZE register field from 0 and OFFSET register field from 8.
Some typical waveforms will look like this.
We will use address 0 to access the Control register.
When we try to write it, we set this write signal to value 1.
We drive the Setup phase and then the Access phase via the PSEL and PENABLE and we specify the value that we want to write with PWDATA.
So in this particular access we try to write value 1 for SIZE and value 1 for OFFSET.
This is a legal combination, so we should expect an OK response.
And then when we try to read the register, so we drive this PWRITE equal to 0, we will get on the PRDATA the same value that we tried to write. 1 for SIZE, 1 for OFFSET.
In this third access, we try to write an illegal combination for SIZE and OFFSET.
SIZE equal to 2 and OFFSET equal to 1 it's an illegal combination so we should expect an error response.
This means that inside the RTL these register fields should not be updated to this value.
So when we try to read again the Control register, we should still get value 1 for the SIZE and value 1 for the OFFSET.
So these should be the values that we wrote here with the first access.
In our tests, we will have to run such scenario in order to prove that this access which returned an error response did not change the values of these register fields.
So, that's the register access interface and now let's look on the RX and TX interfaces.
Both of these interfaces are implementing the same protocol called MD.
MD stands for Memory Data.
This is a made-up protocol only for this training so you will not find any documentation online for this.
Let's see some waveforms with the transfers on the RX and TX interface to better understand this protocol.
The signals part of the RX interface will have as prefix this md_rx_*.
In the same manner on the TX interface the signals will have the prefix md_tx_*.
In both of these interfaces we will have the same group of signals.
A transfer starts when valid becomes 1 and it will end when ready becomes 1.
So, we can have a transfer in only one clock cycle if valid and ready are high at the same time, or we can have a transfer lasting for more than one clock cycle, in which case these signals, valid, data, offset and size will have to remain constant until ready becomes 1.
On the data signal, we have our 4 bytes of information and we specify which of these bytes are valid via the offset and size.
So when offset is 0 and size is 1, the first byte is valid.
When offset is 1 and size is 1, the second byte is valid.
And in this third example, we have offset 2 and size 2, so this means that these last 2 bytes are valid.
We can get the response of each transfer via the error signal.
This error signal is valid when ready is high.
So these first three transfers have an OK response.
And this has an error response because a combination of offset equal to 1 and size equal to 2 is an illegal combination.
And on the RX interface we should expect an error for such a transfer.
On the TX interface we have exactly the same protocol.
So in this example on the TX interface we have 4 bytes of information starting from offset 0.
These bytes on the TX interface are exactly the bytes that we received on the RX interface.
So here we received these 11, 22 and then 33 and 44 together in this third transfer.
On the TX interface these bytes are aligned from offset 0 and sent out in one single transfer.
That's it for this tutorial.
We talked about the features of our DUT.
So we talked about the alignment functionality, the drop counter and its clear feature.
We talked about the RX and TX FIFO levels, the interrupt requests and the register accesses.
Our Aligner has two protocols for its interfaces.
We have the APB protocol for the Register Access interface and then we have the MD protocol for the RX and TX interfaces.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
