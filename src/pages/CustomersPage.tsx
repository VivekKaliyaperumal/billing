import { useState } from 'react';
import { Users, Plus, Phone, CreditCard, Wallet, Search, ChevronDown, ChevronUp, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { useCustomers } from '@/context/CustomerContext';
import { useSettings } from '@/context/SettingsContext';
import { useAuth } from '@/context/AuthContext';
import { toast } from '@/hooks/use-toast';
import { errorMessage } from '@/lib/api/client';
import { cn } from '@/lib/utils';

export default function CustomersPage() {
  const { customers, addCustomer, addPayment, deleteCustomer, getCustomerById, getTotalPendingAmount } = useCustomers();
  const { formatPrice } = useSettings();
  const { isOwner } = useAuth();
  const [busy, setBusy] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [isPaymentOpen, setIsPaymentOpen] = useState(false);
  const [selectedCustomerId, setSelectedCustomerId] = useState<string | null>(null);
  const [expandedCustomer, setExpandedCustomer] = useState<string | null>(null);
  
  const [newName, setNewName] = useState('');
  const [newPhone, setNewPhone] = useState('');
  const [paymentAmount, setPaymentAmount] = useState('');

  const filteredCustomers = customers.filter(c =>
    c.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    c.phone.includes(searchQuery)
  );

  const handleAddCustomer = async () => {
    if (!newName.trim() || !newPhone.trim()) {
      toast({ title: 'Error', description: 'Please fill all fields', variant: 'destructive' });
      return;
    }
    setBusy(true);
    try {
      await addCustomer({ name: newName.trim(), phone: newPhone.trim() });
    } catch (e) {
      toast({ title: 'Could not add customer', description: errorMessage(e), variant: 'destructive' });
      return;
    } finally {
      setBusy(false);
    }
    setNewName('');
    setNewPhone('');
    setIsAddOpen(false);
    toast({ title: 'Customer added', description: `${newName} has been added.` });
  };

  const handleAddPayment = async () => {
    const amount = parseFloat(paymentAmount);
    const pending = selectedCustomerId ? getCustomerById(selectedCustomerId)?.pendingAmount ?? 0 : 0;
    if (!selectedCustomerId || isNaN(amount) || amount <= 0 || !/^\d+(\.\d{1,2})?$/.test(paymentAmount.trim())) {
      toast({ title: 'Error', description: 'Please enter a valid amount', variant: 'destructive' });
      return;
    }
    if (amount > pending) {
      toast({ title: 'Error', description: `Payment is more than the pending amount (${formatPrice(pending)})`, variant: 'destructive' });
      return;
    }
    setBusy(true);
    try {
      await addPayment(selectedCustomerId, amount, 'Payment received');
    } catch (e) {
      toast({ title: 'Payment not recorded', description: errorMessage(e), variant: 'destructive' });
      return;
    } finally {
      setBusy(false);
    }
    setPaymentAmount('');
    setIsPaymentOpen(false);
    toast({ title: 'Payment recorded', description: `Payment of ${formatPrice(amount)} received.` });
  };

  const handleDeleteCustomer = async (id: string, name: string) => {
    if (!window.confirm(`Delete ${name}? Their history will be removed from this list.`)) return;
    try {
      await deleteCustomer(id);
    } catch (e) {
      toast({ title: 'Could not delete customer', description: errorMessage(e), variant: 'destructive' });
      return;
    }
    toast({ title: 'Customer deleted', description: `${name} has been removed.` });
  };

  const customersWithPending = customers.filter(c => c.pendingAmount > 0);

  return (
    <div className="container py-8">
      <div className="mb-8">
        <div className="flex items-center justify-between flex-wrap gap-4">
          <div className="flex items-center gap-3">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl gradient-accent shadow-glow-accent">
              <Users className="h-6 w-6 text-accent-foreground" />
            </div>
            <div>
              <h1 className="font-display text-3xl font-bold text-foreground">Customers</h1>
              <p className="text-muted-foreground">{customers.length} registered customers</p>
            </div>
          </div>
          
          <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
            <DialogTrigger asChild>
              <Button size="lg" className="gradient-primary text-primary-foreground shadow-medium">
                <Plus className="h-5 w-5" />
                Add Customer
              </Button>
            </DialogTrigger>
            <DialogContent className="bg-card border-border">
              <DialogHeader>
                <DialogTitle className="font-display">Add New Customer</DialogTitle>
              </DialogHeader>
              <div className="space-y-4 pt-4">
                <div className="space-y-2">
                  <Label>Name</Label>
                  <Input
                    value={newName}
                    onChange={e => setNewName(e.target.value)}
                    placeholder="Customer name"
                    className="h-12"
                  />
                </div>
                <div className="space-y-2">
                  <Label>Phone Number</Label>
                  <Input
                    value={newPhone}
                    onChange={e => setNewPhone(e.target.value)}
                    placeholder="Phone number"
                    className="h-12"
                  />
                </div>
                <Button onClick={handleAddCustomer} disabled={busy} className="w-full gradient-primary text-primary-foreground">
                  Add Customer
                </Button>
              </div>
            </DialogContent>
          </Dialog>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3 mb-8">
        <Card className="border-border shadow-medium overflow-hidden">
          <div className="h-1 gradient-accent" />
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground flex items-center gap-2">
              <Wallet className="h-4 w-4" />
              Total Pending
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-3xl font-bold text-accent">{formatPrice(getTotalPendingAmount())}</p>
            <p className="text-sm text-muted-foreground mt-1">{customersWithPending.length} customers with dues</p>
          </CardContent>
        </Card>
      </div>

      {/* Search */}
      <div className="relative mb-6">
        <Search className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-muted-foreground" />
        <Input
          placeholder="Search customers by name or phone..."
          value={searchQuery}
          onChange={e => setSearchQuery(e.target.value)}
          className="h-12 pl-12"
        />
      </div>

      {/* Customer List */}
      <div className="space-y-3">
        {filteredCustomers.length === 0 ? (
          <Card className="border-dashed border-border">
            <CardContent className="flex flex-col items-center justify-center py-12">
              <Users className="h-12 w-12 text-muted-foreground mb-4" />
              <p className="text-muted-foreground">No customers found</p>
            </CardContent>
          </Card>
        ) : (
          filteredCustomers.map(customer => (
            <Card 
              key={customer.id} 
              className={cn(
                "border-border shadow-soft transition-all duration-200",
                customer.pendingAmount > 0 && "border-l-4 border-l-accent"
              )}
            >
              <CardContent className="p-4">
                <div 
                  className="flex items-center justify-between cursor-pointer"
                  onClick={() => setExpandedCustomer(expandedCustomer === customer.id ? null : customer.id)}
                >
                  <div className="flex items-center gap-4">
                    <div className="flex h-12 w-12 items-center justify-center rounded-full bg-secondary">
                      <span className="text-lg font-bold text-foreground">
                        {customer.name.charAt(0).toUpperCase()}
                      </span>
                    </div>
                    <div>
                      <h3 className="font-semibold text-foreground">{customer.name}</h3>
                      <p className="text-sm text-muted-foreground flex items-center gap-1">
                        <Phone className="h-3 w-3" />
                        {customer.phone}
                      </p>
                    </div>
                  </div>
                  
                  <div className="flex items-center gap-3">
                    {customer.pendingAmount > 0 && (
                      <div className="text-right">
                        <p className="text-sm text-muted-foreground">Pending</p>
                        <p className="text-lg font-bold text-accent">{formatPrice(customer.pendingAmount)}</p>
                      </div>
                    )}
                    {customer.pendingAmount > 0 && (
                      <Button
                        size="sm"
                        variant="outline"
                        className="border-success text-success hover:bg-success hover:text-success-foreground"
                        onClick={(e) => {
                          e.stopPropagation();
                          setSelectedCustomerId(customer.id);
                          setIsPaymentOpen(true);
                        }}
                      >
                        <CreditCard className="h-4 w-4" />
                        Pay
                      </Button>
                    )}
                    {expandedCustomer === customer.id ? (
                      <ChevronUp className="h-5 w-5 text-muted-foreground" />
                    ) : (
                      <ChevronDown className="h-5 w-5 text-muted-foreground" />
                    )}
                  </div>
                </div>

                {/* Only a customer with nothing pending can be deleted */}
                {expandedCustomer === customer.id && isOwner && customer.pendingAmount === 0 && (
                  <div className="mt-4 flex justify-end">
                    <Button
                      size="sm"
                      variant="outline"
                      className="border-destructive text-destructive hover:bg-destructive hover:text-destructive-foreground"
                      onClick={() => handleDeleteCustomer(customer.id, customer.name)}
                    >
                      <Trash2 className="h-4 w-4" />
                      Delete customer
                    </Button>
                  </div>
                )}

                {/* Transaction History */}
                {expandedCustomer === customer.id && customer.transactions.length > 0 && (
                  <div className="mt-4 pt-4 border-t border-border">
                    <h4 className="text-sm font-medium text-muted-foreground mb-2">Transaction History</h4>
                    <div className="space-y-2 max-h-48 overflow-y-auto">
                      {customer.transactions.slice().reverse().map(t => (
                        <div key={t.id} className="flex items-center justify-between text-sm p-2 rounded-lg bg-secondary/50">
                          <div>
                            <span className={t.type === 'credit' ? 'text-accent' : 'text-success'}>
                              {t.type === 'credit' ? 'Credit' : 'Payment'}
                            </span>
                            <span className="text-muted-foreground ml-2">- {t.description}</span>
                          </div>
                          <div className="text-right">
                            <span className={cn(
                              "font-medium",
                              t.type === 'credit' ? 'text-accent' : 'text-success'
                            )}>
                              {t.type === 'credit' ? '+' : '-'}{formatPrice(t.amount)}
                            </span>
                            <p className="text-xs text-muted-foreground">
                              {new Date(t.date).toLocaleDateString()}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          ))
        )}
      </div>

      {/* Payment Dialog */}
      <Dialog open={isPaymentOpen} onOpenChange={setIsPaymentOpen}>
        <DialogContent className="bg-card border-border">
          <DialogHeader>
            <DialogTitle className="font-display">Record Payment</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 pt-4">
            <div className="space-y-2">
              <Label>Payment Amount</Label>
              <Input
                type="number"
                value={paymentAmount}
                onChange={e => setPaymentAmount(e.target.value)}
                placeholder="Enter amount"
                className="h-12"
              />
            </div>
            <Button onClick={handleAddPayment} disabled={busy} className="w-full gradient-success text-success-foreground">
              <CreditCard className="h-5 w-5" />
              Record Payment
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
